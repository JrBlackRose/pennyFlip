import 'package:flutter/material.dart';

import '../../testing/self_test_runner.dart';
import '../../theme/app_theme.dart';
import '../widgets/status_pill.dart';

class SelfTestScreen extends StatefulWidget {
  const SelfTestScreen({super.key});

  @override
  State<SelfTestScreen> createState() => _SelfTestScreenState();
}

class _SelfTestScreenState extends State<SelfTestScreen> {
  List<SelfTestCaseResult>? _results;
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = null;
    });
    // Run on a microtask boundary so the spinner actually paints before the
    // (fast but synchronous) regex/math engines execute.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final results = SelfTestRunner.runAll();
    if (!mounted) return;
    setState(() {
      _results = results;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final allPass = results != null && results.every((r) => r.verdict == SelfTestVerdict.pass);

    return Scaffold(
      appBar: AppBar(title: const Text('Self-Test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ON-DEVICE ENGINE VERIFICATION',
                      style: AppTheme.mono(size: 12, weight: FontWeight.w800, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  Text(
                    'Runs the exact math (ATR, bandwidth, friction edge, position sizing) and '
                    'regex dictionaries (catalyst tags, dump-trap veto) against two fully '
                    'synthetic, offline fixtures — no network or database access.',
                    style: AppTheme.mono(size: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _running ? null : _run,
                      icon: _running
                          ? const SizedBox(
                              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.science_outlined, size: 18),
                      label: Text(_running ? 'Running…' : 'Run Self-Test'),
                    ),
                  ),
                  if (results != null) ...[
                    const SizedBox(height: 12),
                    StatusPill(
                      label: allPass ? 'ALL TESTS PASSED' : 'TEST FAILURES DETECTED',
                      kind: allPass ? SignalKind.pass : SignalKind.fail,
                      icon: allPass ? Icons.check_circle_outline : Icons.error_outline,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (results != null)
            for (final r in results) ...[
              _CaseCard(result: r),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final SelfTestCaseResult result;
  const _CaseCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final pass = result.verdict == SelfTestVerdict.pass;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${result.caseId} — CIK ${result.cik10}',
                      style: AppTheme.mono(size: 13, weight: FontWeight.w800)),
                ),
                StatusPill(
                  label: pass ? 'PASS' : 'FAIL',
                  kind: pass ? SignalKind.pass : SignalKind.fail,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(result.description, style: AppTheme.mono(size: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            for (final a in result.assertions) ...[
              _AssertionRow(assertion: a),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssertionRow extends StatelessWidget {
  final SelfTestAssertion assertion;
  const _AssertionRow({required this.assertion});

  @override
  Widget build(BuildContext context) {
    final color = assertion.ok ? AppColors.signalPass : AppColors.signalFail;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(assertion.ok ? Icons.check_circle : Icons.cancel, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(assertion.label, style: AppTheme.mono(size: 11.5, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(assertion.detail, style: AppTheme.mono(size: 10.5, color: AppColors.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}
