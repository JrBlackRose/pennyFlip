import 'kill_switch_service.dart';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/entity.dart';
import '../models/filing.dart';
import '../models/pipeline_result.dart';
import 'alpaca_client.dart';
import 'backtest_engine_service.dart';
import 'broker_compliance_service.dart';
import 'pattern_hunter_service.dart';
import 'sec_edgar_service.dart';
import 'settings_service.dart';

/// Ties Modules 1–4 together into one scan cycle over a rotating slice of
/// the cached SEC universe.
///
/// Zero-budget, on-device reality check: the full EDGAR+XBRL+bars pipeline
/// cannot run against the entire ~8,000-entity microcap universe every
/// polling tick within SEC's <10 req/sec fair-access limit and still leave
/// headroom for the broker API. So each cycle advances a persisted cursor
/// through [batchSize] CIKs at a time (round-robin), meaning the full
/// universe is swept over many cycles across the trading day rather than
/// instantaneously. This is the honest trade-off for "runs entirely on a
/// phone, costs nothing" versus a server-side scanner with a real cluster
/// behind it.
class ScanOrchestrator {
  ScanOrchestrator._internal();
  static final ScanOrchestrator instance = ScanOrchestrator._internal();

  static const _cursorKey = 'scan_cursor_cik_index';
  static const _directorySyncedAtKey = 'scan_universe_synced_at';
  static const _directoryStaleAfter = Duration(hours: 24);

  final _controller = StreamController<CandidateResult>.broadcast();
  Stream<CandidateResult> get updates => _controller.stream;

  bool _running = false;
  bool get isRunning => _running;

  Future<void> ensureUniverseFresh() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncedMs = prefs.getInt(_directorySyncedAtKey);
    final isStale = lastSyncedMs == null ||
        DateTime.now().toUtc().difference(DateTime.fromMillisecondsSinceEpoch(lastSyncedMs, isUtc: true)) >
            _directoryStaleAfter;
    if (!isStale) return;

    final entities = await SecEdgarService.instance.fetchMasterCikDirectory();
    for (final e in entities) {
      await AppDatabase.instance.upsertEntity(e);
    }
    await prefs.setInt(_directorySyncedAtKey, DateTime.now().toUtc().millisecondsSinceEpoch);
  }

  /// Runs one scan cycle over the next [batchSize] CIKs in the rotation.
  /// Returns summary counts for logging / notification text.
  Future<ScanCycleSummary> runCycle({int batchSize = 15, String trigger = 'background'}) async {
    if (_running) {
      return const ScanCycleSummary(scanned: 0, approved: 0, skipped: true);
    }
    _running = true;
    final startedAt = DateTime.now();
    final runId = await AppDatabase.instance.startScanRun(trigger: trigger, startedAt: startedAt);

    var scanned = 0;
    var approved = 0;

    try {
      // First priority on every tick: check open trades & auto-stop any position going wrong
      await KillSwitchService.monitorActiveTrades();
      if ((await SettingsService.instance.getDaemonManualOverride()) == 'force_off') {
        return const ScanCycleSummary(scanned: 0, approved: 0, skipped: true);
      }
      await ensureUniverseFresh();
      final batch = await _nextBatch(batchSize);
      final autoTradeEnabled = await SettingsService.instance.getAutoTradeEnabled();

      for (final entity in batch) {
        scanned++;
        final result = await _evaluateOne(entity, autoTradeEnabled: autoTradeEnabled);
        if (result != null) {
          _controller.add(result);
          if (result.outcome == StageOutcome.pass && result.stage == PipelineStage.approved) {
            approved++;
          }
        }
      }
    } finally {
      _running = false;
      await AppDatabase.instance.finishScanRun(
        runId,
        finishedAt: DateTime.now(),
        scanned: scanned,
        approved: approved,
      );
    }

    return ScanCycleSummary(scanned: scanned, approved: approved, skipped: false);
  }

  Future<List<Entity>> _nextBatch(int batchSize) async {
    final db = await AppDatabase.instance.database;
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getInt(_cursorKey) ?? 0;

    final rows = await db.query('entities', orderBy: 'cik10 ASC');
    if (rows.isEmpty) return [];

    final all = rows.map(Entity.fromMap).toList();
    final start = cursor % all.length;
    final out = <Entity>[];
    for (var i = 0; i < batchSize && i < all.length; i++) {
      out.add(all[(start + i) % all.length]);
    }
    await prefs.setInt(_cursorKey, (start + batchSize) % all.length);
    return out;
  }

  /// Runs the full Module 1 -> 2 -> 3 -> 4 pipeline for a single entity,
  /// streaming an intermediate [CandidateResult] at every stage so the UI
  /// pipeline funnel can show exactly where a candidate stopped.
  Future<CandidateResult?> _evaluateOne(Entity entity, {required bool autoTradeEnabled}) async {
    final ticker = entity.latestTicker ?? entity.cik10;

    // --- Module 1 --------------------------------------------------------
    SubmissionsResult submissions;
    try {
      submissions = await SecEdgarService.instance.fetchSubmissions(entity.cik10);
    } catch (_) {
      return null; // network/EDGAR hiccup — skip silently this cycle, retry next rotation
    }

    for (final f in submissions.filings) {
      await AppDatabase.instance.upsertFiling(f);
    }
    if (submissions.tickers.isNotEmpty) {
      await AppDatabase.instance.recordTickerObservation(
          entity.cik10, submissions.tickers.first, DateTime.now());
    }

    double? sharesOutstanding;
    try {
      sharesOutstanding = await SecEdgarService.instance.fetchSharesOutstanding(entity.cik10);
    } catch (_) {
      sharesOutstanding = null;
    }

    await AppDatabase.instance.upsertEntity(entity.copyWith(
      isDelisted: submissions.isDelisted,
      sharesOutstanding: sharesOutstanding,
      sharesOutstandingAsOf: sharesOutstanding != null ? DateTime.now() : null,
      lastSyncedAt: DateTime.now(),
      latestTicker: submissions.tickers.isNotEmpty ? submissions.tickers.first : entity.latestTicker,
    ));

    AlpacaAsset? asset;
    try {
      asset = await AlpacaClient.instance.getAsset(ticker);
    } catch (_) {
      asset = null;
    }

    final module1 = Module1Result(
      passed: !submissions.isDelisted &&
          asset != null &&
          asset.passesPhase0Gate &&
          sharesOutstanding != null,
      isDelisted: submissions.isDelisted,
      tradableOnBroker: asset?.tradable ?? false,
      exchangeOtc: asset?.exchange == 'OTC',
      sharesOutstanding: sharesOutstanding,
      failReason: submissions.isDelisted
          ? 'Flagged delisted (empty tickers or deregistration form on file)'
          : (asset == null
              ? 'Not found on broker'
              : (!asset.passesPhase0Gate
                  ? 'Failed Phase 0 gate (status=${asset.status}, tradable=${asset.tradable}, exchange=${asset.exchange})'
                  : (sharesOutstanding == null ? 'No XBRL shares outstanding on file' : null))),
    );

    var result = CandidateResult(
      cik10: entity.cik10,
      ticker: ticker,
      name: entity.name,
      evaluatedAt: DateTime.now(),
      stage: PipelineStage.module1Data,
      outcome: module1.passed ? StageOutcome.pass : StageOutcome.fail,
      module1: module1,
    );
    _controller.add(result);
    if (!module1.passed) return result;

    // --- Penny Stock Price Guard ($0.05 to $5.00) ---
    // Fetch recent bars to inspect current price level before running compute-heavy pattern scanning


    if (rawBars.isNotEmpty) {
      final latestClose = (rawBars.last['c'] as num?)?.toDouble() ?? 0.0;
      if (latestClose > 5.00 || latestClose < 0.05) {
        result = result.copyWith(
          stage: PipelineStage.module1Data,
          outcome: StageOutcome.fail,
          module1: Module1Result(
            passed: false,
            isDelisted: submissions.isDelisted,
            tradableOnBroker: asset?.tradable ?? false,
            exchangeOtc: asset?.exchange == 'OTC',
            sharesOutstanding: sharesOutstanding,
            failReason: 'Price Filter: \$$latestClose is outside penny range (\$0.05 - \$5.00)',
          ),
        );
        _controller.add(result);
        return result;
      }
    }

    // --- Module 2 ----------------------------------------------------------
    try {
      rawBars = await AlpacaClient.instance.getRawDailyBars(ticker, limit: 180);
    } catch (_) {
      rawBars = const [];
    }
    if (rawBars.length < 150) {
      result = result.copyWith(
        stage: PipelineStage.module2Pattern,
        outcome: StageOutcome.fail,
        module2: Module2Result(
          passed: false,
          bandwidth: 0,
          volumeDryUp: 0,
          baseQualifies: false,
          breakoutQualifies: false,
          demandRatio: 0,
          demandRatioQualifies: false,
          volumeSurgeQualifies: false,
          projectedUpsidePct: 0,
          catalystTags: const [],
          failReason: 'Insufficient broker bar history (${rawBars.length}/150 days)',
        ),
      );
      _controller.add(result);
      return result;
    }

    final bars = rawBars
        .map((b) => OhlcvBar(
              cik10: entity.cik10,
              symbolAtBar: ticker,
              date: DateTime.parse(b['t'] as String),
              open: (b['o'] as num).toDouble(),
              high: (b['h'] as num).toDouble(),
              low: (b['l'] as num).toDouble(),
              close: (b['c'] as num).toDouble(),
              volume: (b['v'] as num).toDouble(),
            ))
        .toList();
    await AppDatabase.instance.upsertBars(bars);

    // Fetch text for recent 8-K style filings only (cheap, high catalyst
    // signal) to keep SEC request volume bounded.
    final candidateFilings =
        submissions.filings.where((f) => f.formType == '8-K' || f.formType == '8-K/A').take(3);
    final filingsWithText = <Filing>[];
    for (final f in candidateFilings) {
      String? text;
      try {
        text = await SecEdgarService.instance.fetchFilingText(f);
      } catch (_) {
        text = null;
      }
      filingsWithText.add(Filing(
        cik10: f.cik10,
        accessionNumber: f.accessionNumber,
        formType: f.formType,
        filedAt: f.filedAt,
        primaryDocUrl: f.primaryDocUrl,
        cachedText: text,
      ));
    }
    for (final f in filingsWithText) {
      await AppDatabase.instance.upsertFiling(f);
    }

    final module2 = PatternHunterService.evaluate(bars: bars, recentFilingTexts: filingsWithText);
    result = result.copyWith(
      stage: PipelineStage.module2Pattern,
      outcome: module2.passed ? StageOutcome.pass : StageOutcome.fail,
      module2: module2,
    );
    _controller.add(result);
    if (!module2.passed) return result;

    // --- Module 3 ----------------------------------------------------------
    final recentFormTypes = submissions.filings.take(20).map((f) => f.formType).toList();
    final module3 = BacktestEngineService.evaluate(
      bars: bars,
      recentFormTypes: recentFormTypes,
      recentFilingTexts: filingsWithText,
      projectedUpsidePct: module2.projectedUpsidePct,
    );
    result = result.copyWith(
      stage: PipelineStage.module3Backtest,
      outcome: module3.vetoed
          ? StageOutcome.veto
          : (module3.passed ? StageOutcome.pass : StageOutcome.fail),
      module3: module3,
    );
    _controller.add(result);
    if (!module3.passed) return result;

    // --- Module 4 ----------------------------------------------------------
    double settledCash = 0;
    try {
      settledCash = await AlpacaClient.instance.getSettledCash();
    } catch (_) {
      settledCash = 0;
    }

    final entryPrice = bars.last.close;
    final stopLossPrice = entryPrice - module3.atr10; // 1x ATR initial stop, consistent with Module 3's own risk unit
    final avgDailyVolume20d =
        _mean(bars.sublist(bars.length - 20).map((b) => b.volume));

    final gateFail = await BrokerComplianceService.phase0Gate(ticker, probeLimitPrice: entryPrice);
    if (gateFail != null) {
      result = result.copyWith(
        stage: PipelineStage.module4Compliance,
        outcome: StageOutcome.fail,
        module4: Module4Result(
          passed: false,
          riskBasedShares: 0,
          cashCappedShares: 0,
          max13dSafeShares: 0,
          maxLiquidityShares: 0,
          approvedShares: 0,
          schedule13dUtilizationPct: 0,
          failReason: gateFail,
        ),
      );
      _controller.add(result);
      return result;
    }

    final module4 = await BrokerComplianceService.evaluateAndRoute(
      symbol: ticker,
      settledCash: settledCash,
      entryPrice: entryPrice,
      stopLossPrice: stopLossPrice,
      // Safe: module1.passed (checked above, with an early return otherwise)
      // requires sharesOutstanding != null, so this can never actually be
      // null here — the local variable just isn't flow-promoted across the
      // async gaps in between.
      sharesOutstanding: sharesOutstanding!,
      avgDailyVolume20d: avgDailyVolume20d,
      autoTradeEnabled: autoTradeEnabled,
    );

    if (module4.routedOrderId != null) {
      await AppDatabase.instance.logOrder(
        cik10: entity.cik10,
        ticker: ticker,
        alpacaOrderId: module4.routedOrderId,
        approvedShares: module4.approvedShares,
        limitPrice: entryPrice,
        stopLossPrice: stopLossPrice,
        status: 'submitted',
        createdAt: DateTime.now(),
      );
    }

    result = result.copyWith(
      stage: module4.passed ? PipelineStage.approved : PipelineStage.module4Compliance,
      outcome: module4.passed ? StageOutcome.pass : StageOutcome.fail,
      module4: module4,
    );
    _controller.add(result);
    return result;
  }

  double _mean(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

class ScanCycleSummary {
  final int scanned;
  final int approved;
  final bool skipped;
  const ScanCycleSummary({required this.scanned, required this.approved, required this.skipped});
}
