/// A single SEC-registered entity, keyed permanently by its 10-digit
/// zero-padded CIK (Central Index Key) — never by mutable ticker symbol,
/// per spec Module 1.
class Entity {
  final String cik10; // e.g. "0000890926"
  final String name;
  final String? latestTicker;
  final String? exchange;
  final bool isDelisted;
  final double? sharesOutstanding; // XBRL dei:EntityCommonStockSharesOutstanding
  final DateTime? sharesOutstandingAsOf;
  final DateTime lastSyncedAt;

  const Entity({
    required this.cik10,
    required this.name,
    this.latestTicker,
    this.exchange,
    this.isDelisted = false,
    this.sharesOutstanding,
    this.sharesOutstandingAsOf,
    required this.lastSyncedAt,
  });

  Entity copyWith({
    String? name,
    String? latestTicker,
    String? exchange,
    bool? isDelisted,
    double? sharesOutstanding,
    DateTime? sharesOutstandingAsOf,
    DateTime? lastSyncedAt,
  }) {
    return Entity(
      cik10: cik10,
      name: name ?? this.name,
      latestTicker: latestTicker ?? this.latestTicker,
      exchange: exchange ?? this.exchange,
      isDelisted: isDelisted ?? this.isDelisted,
      sharesOutstanding: sharesOutstanding ?? this.sharesOutstanding,
      sharesOutstandingAsOf: sharesOutstandingAsOf ?? this.sharesOutstandingAsOf,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'cik10': cik10,
        'name': name,
        'latest_ticker': latestTicker,
        'exchange': exchange,
        'is_delisted': isDelisted ? 1 : 0,
        'shares_outstanding': sharesOutstanding,
        'shares_outstanding_as_of': sharesOutstandingAsOf?.toIso8601String(),
        'last_synced_at': lastSyncedAt.toIso8601String(),
      };

  factory Entity.fromMap(Map<String, Object?> m) => Entity(
        cik10: m['cik10'] as String,
        name: m['name'] as String,
        latestTicker: m['latest_ticker'] as String?,
        exchange: m['exchange'] as String?,
        isDelisted: (m['is_delisted'] as int? ?? 0) == 1,
        sharesOutstanding: (m['shares_outstanding'] as num?)?.toDouble(),
        sharesOutstandingAsOf: m['shares_outstanding_as_of'] != null
            ? DateTime.parse(m['shares_outstanding_as_of'] as String)
            : null,
        lastSyncedAt: DateTime.parse(m['last_synced_at'] as String),
      );
}

/// Historical ticker <-> CIK mapping row (tickers are mutable; CIK is not).
class TickerHistoryRow {
  final String cik10;
  final String ticker;
  final DateTime observedAt;

  const TickerHistoryRow({
    required this.cik10,
    required this.ticker,
    required this.observedAt,
  });

  Map<String, Object?> toMap() => {
        'cik10': cik10,
        'ticker': ticker,
        'observed_at': observedAt.toIso8601String(),
      };

  factory TickerHistoryRow.fromMap(Map<String, Object?> m) => TickerHistoryRow(
        cik10: m['cik10'] as String,
        ticker: m['ticker'] as String,
        observedAt: DateTime.parse(m['observed_at'] as String),
      );
}
