import 'package:flutter_test/flutter_test.dart';
import 'package:pennyflip/testing/self_test_runner.dart';

void main() {
  test('On-Device Quant Engine Self-Test (APXM Pass & HPMP Dump-Trap Veto)', () {
    final results = SelfTestRunner.runAll();
    expect(results.length, 2);

    final apxm = results.firstWhere((r) => r.caseId == 'APXM');
    for (final a in apxm.assertions) {
      // ignore: avoid_print
      print('[APXM] ${a.ok ? "PASS" : "FAIL"}: ${a.label} (${a.detail})');
      expect(a.ok, isTrue, reason: 'APXM failed on: ${a.label}');
    }
    expect(apxm.verdict, SelfTestVerdict.pass);

    final hpmp = results.firstWhere((r) => r.caseId == 'HPMP');
    for (final a in hpmp.assertions) {
      // ignore: avoid_print
      print('[HPMP] ${a.ok ? "PASS" : "FAIL"}: ${a.label} (${a.detail})');
      expect(a.ok, isTrue, reason: 'HPMP failed on: ${a.label}');
    }
    expect(hpmp.verdict, SelfTestVerdict.pass);
  });
}
