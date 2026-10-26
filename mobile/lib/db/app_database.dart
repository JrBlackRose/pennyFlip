import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/entity.dart';
import '../models/filing.dart';

/// Local SQLite layer for pennyFlip (spec Module 1).
///
/// Every table is keyed by the permanent 10-digit zero-padded SEC CIK, never
/// by mutable ticker symbol, so a ticker re-use or a reverse split never
/// corrupts history — this is what "survivorship-free" means in the spec.
class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'pennyflip.sqlite');

    return openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE entities (
            cik10 TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            latest_ticker TEXT,
            exchange TEXT,
            is_delisted INTEGER NOT NULL DEFAULT 0,
            shares_outstanding REAL,
            shares_outstanding_as_of TEXT,
            last_synced_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE ticker_history (
            cik10 TEXT NOT NULL,
            ticker TEXT NOT NULL,
            observed_at TEXT NOT NULL,
            PRIMARY KEY (cik10, ticker, observed_at),
            FOREIGN KEY (cik10) REFERENCES entities(cik10) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_ticker_history_ticker ON ticker_history(ticker)');

        await db.execute('''
          CREATE TABLE filings (
            cik10 TEXT NOT NULL,
            accession_number TEXT NOT NULL,
            form_type TEXT NOT NULL,
            filed_at TEXT NOT NULL,
            primary_doc_url TEXT,
            cached_text TEXT,
            PRIMARY KEY (cik10, accession_number),
            FOREIGN KEY (cik10) REFERENCES entities(cik10) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_filings_cik_filed ON filings(cik10, filed_at DESC)');
        await db.execute('CREATE INDEX idx_filings_form ON filings(form_type)');

        await db.execute('''
          CREATE TABLE ohlcv_bars (
            cik10 TEXT NOT NULL,
            symbol_at_bar TEXT NOT NULL,
            date TEXT NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL,
            PRIMARY KEY (cik10, date),
            FOREIGN KEY (cik10) REFERENCES entities(cik10) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX idx_bars_cik_date ON ohlcv_bars(cik10, date DESC)');

        await db.execute('''
          CREATE TABLE scan_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            started_at TEXT NOT NULL,
            finished_at TEXT,
            candidates_scanned INTEGER NOT NULL DEFAULT 0,
            candidates_approved INTEGER NOT NULL DEFAULT 0,
            trigger TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE orders_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            cik10 TEXT NOT NULL,
            ticker TEXT NOT NULL,
            alpaca_order_id TEXT,
            approved_shares INTEGER NOT NULL,
            limit_price REAL NOT NULL,
            stop_loss_price REAL,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ---------------------------------------------------------------------
  // Entities
  // ---------------------------------------------------------------------

  Future<void> upsertEntity(Entity e) async {
    final db = await database;
    await db.insert('entities', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Entity?> getEntity(String cik10) async {
    final db = await database;
    final rows = await db.query('entities', where: 'cik10 = ?', whereArgs: [cik10]);
    if (rows.isEmpty) return null;
    return Entity.fromMap(rows.first);
  }

  Future<void> recordTickerObservation(String cik10, String ticker, DateTime observedAt) async {
    final db = await database;
    await db.insert(
      'ticker_history',
      TickerHistoryRow(cik10: cik10, ticker: ticker, observedAt: observedAt).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ---------------------------------------------------------------------
  // Filings
  // ---------------------------------------------------------------------

  Future<void> upsertFiling(Filing f) async {
    final db = await database;
    await db.insert('filings', f.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Filing>> recentFilings(String cik10, {int limit = 50}) async {
    final db = await database;
    final rows = await db.query(
      'filings',
      where: 'cik10 = ?',
      whereArgs: [cik10],
      orderBy: 'filed_at DESC',
      limit: limit,
    );
    return rows.map(Filing.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // OHLCV bars
  // ---------------------------------------------------------------------

  Future<void> upsertBars(List<OhlcvBar> bars) async {
    final db = await database;
    final batch = db.batch();
    for (final bar in bars) {
      batch.insert('ohlcv_bars', bar.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Bars ordered oldest -> newest, most recent `limit` trading days.
  Future<List<OhlcvBar>> recentBars(String cik10, {int limit = 120}) async {
    final db = await database;
    final rows = await db.query(
      'ohlcv_bars',
      where: 'cik10 = ?',
      whereArgs: [cik10],
      orderBy: 'date DESC',
      limit: limit,
    );
    return rows.reversed.map(OhlcvBar.fromMap).toList();
  }

  // ---------------------------------------------------------------------
  // Scan runs / orders log
  // ---------------------------------------------------------------------

  Future<int> startScanRun({required String trigger, required DateTime startedAt}) async {
    final db = await database;
    return db.insert('scan_runs', {
      'started_at': startedAt.toIso8601String(),
      'trigger': trigger,
      'candidates_scanned': 0,
      'candidates_approved': 0,
    });
  }

  Future<void> finishScanRun(int id,
      {required DateTime finishedAt, required int scanned, required int approved}) async {
    final db = await database;
    await db.update(
      'scan_runs',
      {
        'finished_at': finishedAt.toIso8601String(),
        'candidates_scanned': scanned,
        'candidates_approved': approved,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> logOrder({
    required String cik10,
    required String ticker,
    String? alpacaOrderId,
    required int approvedShares,
    required double limitPrice,
    double? stopLossPrice,
    required String status,
    required DateTime createdAt,
  }) async {
    final db = await database;
    await db.insert('orders_log', {
      'cik10': cik10,
      'ticker': ticker,
      'alpaca_order_id': alpacaOrderId,
      'approved_shares': approvedShares,
      'limit_price': limitPrice,
      'stop_loss_price': stopLossPrice,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> recentOrders({int limit = 50}) async {
    final db = await database;
    return db.query('orders_log', orderBy: 'created_at DESC', limit: limit);
  }

  /// Wipes all locally cached market/filing data (keeps settings, which live
  /// in flutter_secure_storage, not here). Used by Settings > "Clear local
  /// data".
  Future<void> wipeAll() async {
    final db = await database;
    await db.delete('ohlcv_bars');
    await db.delete('filings');
    await db.delete('ticker_history');
    await db.delete('entities');
    await db.delete('orders_log');
    await db.delete('scan_runs');
  }
}
