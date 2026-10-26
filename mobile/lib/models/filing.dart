import 'engine_types.dart';

/// A single SEC EDGAR filing, stored locally so the Module 2 regex catalyst
/// engine and the Module 3 crash-correlation veto can both run against the
/// same cached filing text without re-hitting EDGAR.
class Filing implements FilingTextLike {
  final String cik10;
  final String accessionNumber;
  final String formType; // e.g. "8-K", "S-3", "15-12G"
  final DateTime filedAt;
  final String? primaryDocUrl;
  final String? cachedText; // sanitized plain text, see CatalystParser.sanitize

  const Filing({
    required this.cik10,
    required this.accessionNumber,
    required this.formType,
    required this.filedAt,
    this.primaryDocUrl,
    this.cachedText,
  });

  Map<String, Object?> toMap() => {
        'cik10': cik10,
        'accession_number': accessionNumber,
        'form_type': formType,
        'filed_at': filedAt.toIso8601String(),
        'primary_doc_url': primaryDocUrl,
        'cached_text': cachedText,
      };

  factory Filing.fromMap(Map<String, Object?> m) => Filing(
        cik10: m['cik10'] as String,
        accessionNumber: m['accession_number'] as String,
        formType: m['form_type'] as String,
        filedAt: DateTime.parse(m['filed_at'] as String),
        primaryDocUrl: m['primary_doc_url'] as String?,
        cachedText: m['cached_text'] as String?,
      );

  /// Forms that flag delisting / deregistration per spec Module 1.
  static const delistingForms = {'15-12G', '15-12B', '15-15D', '25', '25-NSE'};

  /// Forms that immediately VETO a setup per spec Module 3 §1 (dilution risk).
  static const crashCorrelationForms = {'S-3', 'S-3/A', '424B5', 'S-1', 'EFFECT'};

  /// FilingTextLike adapter: the engine modules match against cachedText
  /// (falls back to empty string if the primary doc hasn't been fetched yet,
  /// which simply means this filing contributes no catalyst/veto matches).
  @override
  String get text => cachedText ?? '';
}

/// One OHLCV daily bar, unadjusted for reverse splits per spec Module 1.
class OhlcvBar implements OhlcvBarLike {
  final String cik10;
  final String symbolAtBar; // ticker as traded on this date
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const OhlcvBar({
    required this.cik10,
    required this.symbolAtBar,
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  Map<String, Object?> toMap() => {
        'cik10': cik10,
        'symbol_at_bar': symbolAtBar,
        'date': date.toIso8601String().substring(0, 10),
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
      };

  factory OhlcvBar.fromMap(Map<String, Object?> m) => OhlcvBar(
        cik10: m['cik10'] as String,
        symbolAtBar: m['symbol_at_bar'] as String,
        date: DateTime.parse(m['date'] as String),
        open: (m['open'] as num).toDouble(),
        high: (m['high'] as num).toDouble(),
        low: (m['low'] as num).toDouble(),
        close: (m['close'] as num).toDouble(),
        volume: (m['volume'] as num).toDouble(),
      );
}
