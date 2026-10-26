/// Which of the 4 pipeline stages a candidate is currently sitting at / was
/// stopped at. Mirrors the "Pipeline Filter Funnel" the UI renders.
enum PipelineStage {
  module1Data, // CIK resolution, delisting check, XBRL float
  module2Pattern, // accumulation base + breakout + catalyst regex
  module3Backtest, // dump-trap veto + synthetic ATR friction edge
  module4Compliance, // position sizing + Alpaca paper routing
  approved, // passed all 4 modules, order routed (or ready to route)
}

enum StageOutcome { pending, pass, fail, veto }

/// Result of Module 1 for one CIK.
class Module1Result {
  final bool passed;
  final bool isDelisted;
  final bool tradableOnBroker;
  final bool exchangeOtc;
  final double? sharesOutstanding;
  final String? failReason;

  const Module1Result({
    required this.passed,
    required this.isDelisted,
    required this.tradableOnBroker,
    required this.exchangeOtc,
    this.sharesOutstanding,
    this.failReason,
  });
}

/// Result of Module 2 for one CIK/breakout bar.
class Module2Result {
  final bool passed;
  final double bandwidth; // accumulation base bandwidth, fraction
  final double volumeDryUp; // fraction
  final bool baseQualifies;
  final bool breakoutQualifies;
  final double demandRatio; // up-volume/down-volume
  final bool demandRatioQualifies;
  final bool volumeSurgeQualifies;
  final double projectedUpsidePct;
  final List<String> catalystTags;
  final bool blockedByPromptInjection;
  final String? failReason;

  const Module2Result({
    required this.passed,
    required this.bandwidth,
    required this.volumeDryUp,
    required this.baseQualifies,
    required this.breakoutQualifies,
    required this.demandRatio,
    required this.demandRatioQualifies,
    required this.volumeSurgeQualifies,
    required this.projectedUpsidePct,
    required this.catalystTags,
    this.blockedByPromptInjection = false,
    this.failReason,
  });
}

/// Result of Module 3 for one CIK.
class Module3Result {
  final bool passed;
  final bool vetoed;
  final List<String> vetoTags; // which crash-correlation patterns fired
  final double atr10;
  final double syntheticSpreadPct;
  final double effectiveFrictionTaxPct;
  final double netExpectedEdgePct;
  final String? failReason;

  const Module3Result({
    required this.passed,
    required this.vetoed,
    required this.vetoTags,
    required this.atr10,
    required this.syntheticSpreadPct,
    required this.effectiveFrictionTaxPct,
    required this.netExpectedEdgePct,
    this.failReason,
  });
}

/// Result of Module 4 for one CIK.
class Module4Result {
  final bool passed;
  final int riskBasedShares;
  final int cashCappedShares;
  final int max13dSafeShares;
  final int maxLiquidityShares;
  final int approvedShares;
  final double schedule13dUtilizationPct; // approvedShares / max13dSafeShares-equivalent, for the gauge
  final String? routedOrderId;
  final String? failReason;

  const Module4Result({
    required this.passed,
    required this.riskBasedShares,
    required this.cashCappedShares,
    required this.max13dSafeShares,
    required this.maxLiquidityShares,
    required this.approvedShares,
    required this.schedule13dUtilizationPct,
    this.routedOrderId,
    this.failReason,
  });
}

/// A candidate moving through the pipeline, carrying the outcome of each
/// module it has reached so far. This is what the Candidate Feed renders.
class CandidateResult {
  final String cik10;
  final String ticker;
  final String name;
  final DateTime evaluatedAt;
  final PipelineStage stage;
  final StageOutcome outcome;

  final Module1Result? module1;
  final Module2Result? module2;
  final Module3Result? module3;
  final Module4Result? module4;

  const CandidateResult({
    required this.cik10,
    required this.ticker,
    required this.name,
    required this.evaluatedAt,
    required this.stage,
    required this.outcome,
    this.module1,
    this.module2,
    this.module3,
    this.module4,
  });

  CandidateResult copyWith({
    PipelineStage? stage,
    StageOutcome? outcome,
    Module1Result? module1,
    Module2Result? module2,
    Module3Result? module3,
    Module4Result? module4,
  }) {
    return CandidateResult(
      cik10: cik10,
      ticker: ticker,
      name: name,
      evaluatedAt: evaluatedAt,
      stage: stage ?? this.stage,
      outcome: outcome ?? this.outcome,
      module1: module1 ?? this.module1,
      module2: module2 ?? this.module2,
      module3: module3 ?? this.module3,
      module4: module4 ?? this.module4,
    );
  }
}
