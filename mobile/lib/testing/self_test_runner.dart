import '../models/engine_types.dart';
import '../models/pipeline_result.dart';
import '../services/backtest_engine_service.dart';
import '../services/broker_compliance_service.dart';
import '../services/pattern_hunter_service.dart';
import 'fixture_bars.dart';

enum SelfTestVerdict { pass, fail }

class SelfTestAssertion {
  final String label;
  final bool ok;
  final String detail;
  const SelfTestAssertion({required this.label, required this.ok, required this.detail});
}

class SelfTestCaseResult {
  final String caseId; // "APXM" or "HPMP"
  final String cik10;
  final String description;
  final SelfTestVerdict verdict;
  final List<SelfTestAssertion> assertions;
  final Module2Result module2;
  final Module3Result module3;
  final Module4Result? module4;

  const SelfTestCaseResult({
    required this.caseId,
    required this.cik10,
    required this.description,
    required this.verdict,
    required this.assertions,
    required this.module2,
    required this.module3,
    this.module4,
  });

  bool get allAssertionsPassed => assertions.every((a) => a.ok);
}

/// On-device self-test harness (spec: "Run Self-Test" button).
///
/// Runs the exact math and regex engines (Module 2, Module 3, Module 4)
/// against two fully synthetic, offline fixtures:
///   - APXM (CIK 0001889901) — expected to PASS every module cleanly.
///   - HPMP (CIK 0001999999) — expected to be VETOED by Module 3's
///     Dump-Trap / Crash-Correlation check.
///
/// No network or database access happens here — this purely verifies the
/// arithmetic and regex dictionaries against known-good inputs/outputs, so
/// it can run instantly and identically on any device.
class SelfTestRunner {
  SelfTestRunner._();

  static const apxmCik = '0001889901';
  static const hpmpCik = '0001999999';

  static List<SelfTestCaseResult> runAll() {
    return [_runApxmPassCase(), _runHpmpVetoCase()];
  }

  static SelfTestCaseResult _runApxmPassCase() {
    final rawBars = buildPassFixtureBars();
    final bars = rawBars
        .map((b) => _FixtureBarAdapter(open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume))
        .toList();
    final filing = buildPassCatalystFiling(apxmCik);

    final module2 = PatternHunterService.evaluate(bars: bars, recentFilingTexts: [filing]);
    final module3 = BacktestEngineService.evaluate(
      bars: bars,
      recentFormTypes: const ['8-K', '10-Q'], // no veto-triggering forms
      recentFilingTexts: [filing],
      projectedUpsidePct: module2.projectedUpsidePct,
    );

    Module4Result? module4;
    if (module3.passed) {
      final entryPrice = rawBars.last.close;
      final stopLossPrice = entryPrice - module3.atr10;
      final avgVol20 = _mean(rawBars.sublist(rawBars.length - 20).map((b) => b.volume));
      // sizePosition() is pure math, no network — exactly what the
      // self-test harness needs to stay fully offline.
      module4 = BrokerComplianceService.sizePosition(
        settledCash: 50000,
        entryPrice: entryPrice,
        stopLossPrice: stopLossPrice,
        sharesOutstanding: 18000000,
        avgDailyVolume20d: avgVol20,
      );
    }

    final assertions = <SelfTestAssertion>[
      SelfTestAssertion(
        label: 'Accumulation base qualifies (bandwidth 5-8%, dry-up 70-90%)',
        ok: module2.baseQualifies,
        detail: 'bandwidth=${_pct(module2.bandwidth)}, dryUp=${_pct(module2.volumeDryUp)}',
      ),
      SelfTestAssertion(
        label: 'Range-ceiling breakout qualifies (hugs 97% of 90d high + demand)',
        ok: module2.breakoutQualifies,
        detail: 'demandRatio=${module2.demandRatio.toStringAsFixed(2)}, '
            'volumeSurge=${module2.volumeSurgeQualifies}',
      ),
      SelfTestAssertion(
        label: 'Catalyst regex matched (definitive_agreement) without prompt-injection block',
        ok: module2.catalystTags.contains('definitive_agreement') && !module2.blockedByPromptInjection,
        detail: 'tags=${module2.catalystTags}',
      ),
      SelfTestAssertion(
        label: 'Module 2 overall PASS',
        ok: module2.passed,
        detail: module2.failReason ?? 'all Module 2 checks satisfied',
      ),
      SelfTestAssertion(
        label: 'No Module 3 Dump-Trap veto triggered',
        ok: !module3.vetoed,
        detail: module3.vetoTags.isEmpty ? 'no veto tags' : 'unexpected veto: ${module3.vetoTags}',
      ),
      SelfTestAssertion(
        label: 'Net expected edge clears +10% after 15% friction floor',
        ok: module3.netExpectedEdgePct >= 0.10,
        detail: 'upside=${_pct(module2.projectedUpsidePct)}, '
            'friction=${_pct(module3.effectiveFrictionTaxPct)}, '
            'netEdge=${_pct(module3.netExpectedEdgePct)}',
      ),
      SelfTestAssertion(
        label: 'Module 3 overall PASS',
        ok: module3.passed,
        detail: module3.failReason ?? 'all Module 3 checks satisfied',
      ),
      if (module4 != null)
        SelfTestAssertion(
          label: 'Module 4 sizing resolves to a positive approved-share count',
          ok: module4.approvedShares > 0,
          detail: 'approved=${module4.approvedShares} '
              '(risk=${module4.riskBasedShares}, cash=${module4.cashCappedShares}, '
              '13d=${module4.max13dSafeShares}, liquidity=${module4.maxLiquidityShares})',
        ),
    ];

    final verdict =
        (module2.passed && module3.passed && (module4?.approvedShares ?? 1) > 0 && assertions.every((a) => a.ok))
            ? SelfTestVerdict.pass
            : SelfTestVerdict.fail;

    return SelfTestCaseResult(
      caseId: 'APXM',
      cik10: apxmCik,
      description: 'Expected: clean PASS through Modules 2, 3 and 4',
      verdict: verdict,
      assertions: assertions,
      module2: module2,
      module3: module3,
      module4: module4,
    );
  }

  static SelfTestCaseResult _runHpmpVetoCase() {
    final rawBars = buildPassFixtureBars(); // same qualifying price/volume shape
    final bars = rawBars
        .map((b) => _FixtureBarAdapter(open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume))
        .toList();
    final filing = buildDumpTrapCatalystFiling(hpmpCik);

    final module2 = PatternHunterService.evaluate(bars: bars, recentFilingTexts: [filing]);
    final module3 = BacktestEngineService.evaluate(
      bars: bars,
      recentFormTypes: const ['8-K', 'S-3'], // S-3 alone is a veto-triggering form
      recentFilingTexts: [filing],
      projectedUpsidePct: module2.projectedUpsidePct,
    );

    final assertions = <SelfTestAssertion>[
      SelfTestAssertion(
        label: 'Module 2 still passes on price/volume shape + catalyst regex '
            '(veto is a Module 3 concern, not Module 2)',
        ok: module2.passed,
        detail: module2.failReason ?? 'tags=${module2.catalystTags}',
      ),
      SelfTestAssertion(
        label: 'S-3 form alone triggers crash-correlation veto',
        ok: module3.vetoTags.contains('sec_form:S-3'),
        detail: 'vetoTags=${module3.vetoTags}',
      ),
      SelfTestAssertion(
        label: 'toxic_convertible_note regex matched filing text',
        ok: module3.vetoTags.contains('toxic_convertible_note'),
        detail: 'matched on "variable conversion price" / "discount to the lowest trading price"',
      ),
      SelfTestAssertion(
        label: 'active_atm_or_424b5_dilution regex matched filing text',
        ok: module3.vetoTags.contains('active_atm_or_424b5_dilution'),
        detail: 'matched on "at-the-market offering"',
      ),
      SelfTestAssertion(
        label: 'Module 3 overall result is VETOED (not a plain fail)',
        ok: module3.vetoed && !module3.passed,
        detail: module3.failReason ?? 'unexpected: not vetoed',
      ),
    ];

    final verdict = (module2.passed && module3.vetoed && assertions.every((a) => a.ok))
        ? SelfTestVerdict.pass
        : SelfTestVerdict.fail;

    return SelfTestCaseResult(
      caseId: 'HPMP',
      cik10: hpmpCik,
      description: 'Expected: Module 2 passes, Module 3 DUMP-TRAP VETO '
          '(S-3 form + 2 toxic-financing regex matches)',
      verdict: verdict,
      assertions: assertions,
      module2: module2,
      module3: module3,
      module4: null,
    );
  }

  static double _mean(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
}

class _FixtureBarAdapter implements OhlcvBarLike {
  @override
  final double open, high, low, close, volume;
  const _FixtureBarAdapter({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });
}
