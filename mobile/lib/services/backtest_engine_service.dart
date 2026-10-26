import '../models/engine_types.dart';
import '../models/pipeline_result.dart';
import '../regex/dump_trap_patterns.dart';
import 'catalyst_parser.dart';

/// Dump-Trap & Friction-Native Backtest Engine — spec Module 3.
///
/// Bars passed in must be ordered oldest -> newest, with the LAST bar being
/// the breakout/entry bar (same convention as Module 2).
class BacktestEngineService {
  BacktestEngineService._();

  static const _atrWindow = 10; // trading days
  static const _spreadMultiplier = 1.5;
  static const _minFrictionFloor = 0.15; // 15% minimum round-trip friction
  static const _minNetEdge = 0.10; // +10% minimum net edge after friction

  static Module3Result evaluate({
    required List<OhlcvBarLike> bars,
    required List<String> recentFormTypes,
    required List<FilingTextLike> recentFilingTexts,
    required double projectedUpsidePct,
  }) {
    // --- 1. Crash-Correlation Veto ---------------------------------------
    final vetoTags = <String>{};

    for (final form in recentFormTypes) {
      if (DumpTrapPatterns.vetoForms.contains(form)) {
        vetoTags.add('sec_form:$form');
      }
    }

    for (final filingText in recentFilingTexts) {
      final clean = CatalystParser.sanitize(filingText.text);
      DumpTrapPatterns.crashCorrelationText.forEach((tag, pattern) {
        if (pattern.hasMatch(clean)) vetoTags.add(tag);
      });
    }

    final vetoed = vetoTags.isNotEmpty;

    // --- 2. Synthetic Volatility Spread Penalty Formula -------------------
    if (bars.length < _atrWindow + 1) {
      return Module3Result(
        passed: false,
        vetoed: vetoed,
        vetoTags: vetoTags.toList(),
        atr10: 0,
        syntheticSpreadPct: 0,
        effectiveFrictionTaxPct: 0,
        netExpectedEdgePct: 0,
        failReason: 'Insufficient bars for ATR_10 (need ${_atrWindow + 1}, have ${bars.length})',
      );
    }

    final atr10 = _computeAtr(bars, _atrWindow);
    final closingPrice = bars.last.close;
    final syntheticSpreadPct = closingPrice == 0 ? 0.0 : (atr10 / closingPrice) * _spreadMultiplier;
    final effectiveFrictionTaxPct =
        syntheticSpreadPct > _minFrictionFloor ? syntheticSpreadPct : _minFrictionFloor;
    final netExpectedEdgePct = projectedUpsidePct - effectiveFrictionTaxPct;

    final edgeOk = netExpectedEdgePct >= _minNetEdge;
    final passed = !vetoed && edgeOk;

    String? failReason;
    if (vetoed) {
      failReason = 'Crash-correlation veto: ${vetoTags.join(', ')}';
    } else if (!edgeOk) {
      failReason = 'Net expected edge ${(netExpectedEdgePct * 100).toStringAsFixed(1)}% '
          '< required 10.0% (upside ${(projectedUpsidePct * 100).toStringAsFixed(1)}% - '
          'friction ${(effectiveFrictionTaxPct * 100).toStringAsFixed(1)}%)';
    }

    return Module3Result(
      passed: passed,
      vetoed: vetoed,
      vetoTags: vetoTags.toList(),
      atr10: atr10,
      syntheticSpreadPct: syntheticSpreadPct,
      effectiveFrictionTaxPct: effectiveFrictionTaxPct,
      netExpectedEdgePct: netExpectedEdgePct,
      failReason: failReason,
    );
  }

  /// 10-day Average True Range. True Range for bar i is
  /// max(high-low, |high-prevClose|, |low-prevClose|); ATR_10 is the simple
  /// mean of the last 10 True Range values ending at the entry bar.
  static double _computeAtr(List<OhlcvBarLike> bars, int window) {
    final trueRanges = <double>[];
    final startIdx = bars.length - window;
    for (var i = startIdx; i < bars.length; i++) {
      final bar = bars[i];
      final prevClose = bars[i - 1].close;
      final tr = [
        bar.high - bar.low,
        (bar.high - prevClose).abs(),
        (bar.low - prevClose).abs(),
      ].reduce((a, b) => a > b ? a : b);
      trueRanges.add(tr);
    }
    return trueRanges.reduce((a, b) => a + b) / trueRanges.length;
  }
}
