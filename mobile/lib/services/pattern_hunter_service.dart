import '../models/engine_types.dart';
import '../models/pipeline_result.dart';
import 'catalyst_parser.dart';

/// Pattern Hunter & Deterministic Catalyst Parser — spec Module 2.
///
/// Bars passed in must be ordered oldest -> newest, with the LAST bar being
/// the candidate breakout bar (today's / most recent session).
class PatternHunterService {
  PatternHunterService._();

  static const _baseWindowMin = 15; // trading days
  static const _baseWindowMax = 30; // trading days
  static const _baselineWindow = 30; // trading days, prior to the base window
  static const _breakoutLookback = 90; // trading days

  static const _bandwidthMin = 0.05;
  static const _bandwidthMax = 0.08;
  static const _dryUpMin = 0.70;
  static const _dryUpMax = 0.90;

  static const _closeToCeilingRatio = 0.97;
  static const _demandRatioMin = 1.40;
  static const _volumeSurgeMultiple = 2.5;
  static const _upsideProjectionMultiplier = 1.25;

  /// Evaluates the full Module 2 pipeline for one candidate.
  ///
  /// [bars] must contain at least `_breakoutLookback + _baseWindowMax +
  /// _baselineWindow` (150) bars to be evaluable; shorter histories fail
  /// with a clear reason rather than silently passing on partial data.
  static Module2Result evaluate({
    required List<OhlcvBarLike> bars,
    required List<FilingTextLike> recentFilingTexts,
  }) {
    final minBarsNeeded = _breakoutLookback + _baseWindowMax + _baselineWindow;
    if (bars.length < minBarsNeeded) {
      return Module2Result(
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
        failReason:
            'Insufficient price history: need $minBarsNeeded trading days, have ${bars.length}',
      );
    }

    final breakoutIndex = bars.length - 1;
    final breakoutBar = bars[breakoutIndex];

    // --- 1. Low-Volume Accumulation Base -------------------------------
    // Spec gives the base window as "15 to 30 trading days prior to the
    // breakout bar" without pinning an exact W, so we scan every window
    // length in that range and accept the base as qualifying the moment any
    // W produces a bandwidth AND volume dry-up both inside their target
    // bands. We keep the first (narrowest) qualifying W for reporting.
    double bestBandwidth = 0;
    double bestDryUp = 0;
    bool baseQualifies = false;

    for (var w = _baseWindowMin; w <= _baseWindowMax; w++) {
      final baseStart = breakoutIndex - w;
      final baselineStart = baseStart - _baselineWindow;
      if (baselineStart < 0) continue;

      final baseSlice = bars.sublist(baseStart, breakoutIndex); // W days prior to breakout
      final baselineSlice = bars.sublist(baselineStart, baseStart); // prior 30d baseline

      final baseHigh = baseSlice.map((b) => b.high).reduce((a, b) => a > b ? a : b);
      final baseLow = baseSlice.map((b) => b.low).reduce((a, b) => a < b ? a : b);
      final bandwidth = baseLow == 0 ? 0.0 : (baseHigh - baseLow) / baseLow;

      final baseMeanVol = _mean(baseSlice.map((b) => b.volume));
      final baselineMeanVol = _mean(baselineSlice.map((b) => b.volume));
      final volumeDryUp = baselineMeanVol == 0 ? 0.0 : 1.0 - (baseMeanVol / baselineMeanVol);

      final bandwidthOk = bandwidth >= _bandwidthMin && bandwidth <= _bandwidthMax;
      final dryUpOk = volumeDryUp >= _dryUpMin && volumeDryUp <= _dryUpMax;

      // Keep the most recently evaluated window's figures for reporting even
      // if it doesn't qualify, so the UI always has something concrete to
      // show; overwrite with the qualifying window's figures the moment one
      // is found.
      if (!baseQualifies) {
        bestBandwidth = bandwidth;
        bestDryUp = volumeDryUp;
      }

      if (bandwidthOk && dryUpOk) {
        baseQualifies = true;
        bestBandwidth = bandwidth;
        bestDryUp = volumeDryUp;
        break;
      }
    }

    // --- 2. Range-Ceiling Breakout ---------------------------------------
    final lookbackStart = breakoutIndex - _breakoutLookback;
    final lookbackSlice = bars.sublist(lookbackStart, breakoutIndex + 1); // inclusive of breakout bar

    final high90 = lookbackSlice.map((b) => b.high).reduce((a, b) => a > b ? a : b);
    final low90 = lookbackSlice.map((b) => b.low).reduce((a, b) => a < b ? a : b);
    final latestClose = breakoutBar.close;

    final hugsCeiling = latestClose >= _closeToCeilingRatio * high90;

    double upVol = 0;
    double downVol = 0;
    for (final b in lookbackSlice) {
      if (b.close > b.open) {
        upVol += b.volume;
      } else if (b.close < b.open) {
        downVol += b.volume;
      }
    }
    final demandRatio = downVol == 0 ? double.infinity : upVol / downVol;
    final demandRatioQualifies = demandRatio >= _demandRatioMin;

    final last15 = bars.sublist(breakoutIndex - 15, breakoutIndex); // excludes breakout bar itself
    final meanVol15 = _mean(last15.map((b) => b.volume));
    final volumeSurgeQualifies =
        meanVol15 > 0 && breakoutBar.volume >= _volumeSurgeMultiple * meanVol15;

    final breakoutQualifies = hugsCeiling && (demandRatioQualifies || volumeSurgeQualifies);

    final projectedUpsidePct =
        latestClose == 0 ? 0.0 : ((high90 - low90) / latestClose) * _upsideProjectionMultiplier;

    // --- 3. Deterministic Regex Catalyst Engine --------------------------
    final catalystTags = <String>{};
    var blockedByPromptInjection = false;
    for (final filingText in recentFilingTexts) {
      final result = CatalystParser.parse(filingText.text);
      if (result.blockedByPromptInjection) {
        blockedByPromptInjection = true;
        continue; // this filing is excluded, others are still evaluated
      }
      catalystTags.addAll(result.tags);
    }

    final passed = baseQualifies && breakoutQualifies && catalystTags.isNotEmpty;

    String? failReason;
    if (!passed) {
      final reasons = <String>[];
      if (!baseQualifies) {
        reasons.add('no W in [15,30] produced bandwidth in [5%,8%] '
            'and volume dry-up in [70%,90%] (best: bandwidth '
            '${(bestBandwidth * 100).toStringAsFixed(1)}%, dry-up '
            '${(bestDryUp * 100).toStringAsFixed(1)}%)');
      }
      if (!breakoutQualifies) {
        if (!hugsCeiling) {
          reasons.add('close ${latestClose.toStringAsFixed(2)} does not hug 97% of '
              '90d high ${high90.toStringAsFixed(2)}');
        } else {
          reasons.add('demand ratio ${demandRatio.toStringAsFixed(2)} < 1.40 and '
              'no 2.5x volume surge');
        }
      }
      if (catalystTags.isEmpty) {
        reasons.add(blockedByPromptInjection
            ? 'only matching filing text was blocked as prompt-injection/hype language'
            : 'no structural catalyst regex matched recent filings');
      }
      failReason = reasons.join('; ');
    }

    return Module2Result(
      passed: passed,
      bandwidth: bestBandwidth,
      volumeDryUp: bestDryUp,
      baseQualifies: baseQualifies,
      breakoutQualifies: breakoutQualifies,
      demandRatio: demandRatio.isFinite ? demandRatio : 999.0,
      demandRatioQualifies: demandRatioQualifies,
      volumeSurgeQualifies: volumeSurgeQualifies,
      projectedUpsidePct: projectedUpsidePct,
      catalystTags: catalystTags.toList(),
      blockedByPromptInjection: blockedByPromptInjection,
      failReason: failReason,
    );
  }

  static double _mean(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
