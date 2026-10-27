import 'package:flutter/material.dart';

import '../../models/pipeline_result.dart';
import '../../theme/app_theme.dart';
import 'status_pill.dart';

class CandidateCard extends StatelessWidget {
  final CandidateResult result;

  const CandidateCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 10),
            _moduleRow(),
            if (result.module1 != null && !result.module1!.passed && result.module1!.failReason != null) ...[
              const SizedBox(height: 10),
              _failLine('M1 Gate: ${result.module1!.failReason!}'),
            ],
            if (result.module2 != null) ...[
              const SizedBox(height: 12),
              _module2Detail(result.module2!),
            ],
            if (result.module3 != null) ...[
              const SizedBox(height: 12),
              _module3Detail(result.module3!),
            ],
            if (result.module4 != null) ...[
              const SizedBox(height: 12),
              _module4Detail(result.module4!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.bgSurfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Text(
            result.ticker.isNotEmpty ? result.ticker.substring(0, 1) : '?',
            style: AppTheme.mono(size: 16, weight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.ticker, style: AppTheme.mono(size: 15, weight: FontWeight.w800)),
              Text('CIK ${result.cik10} · ${result.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(size: 11, color: AppColors.textTertiary)),
            ],
          ),
        ),
        _overallPill(),
      ],
    );
  }

  Widget _overallPill() {
    switch (result.outcome) {
      case StageOutcome.pass:
        return StatusPill(
          label: result.stage == PipelineStage.approved ? 'APPROVED' : 'PASS',
          kind: SignalKind.pass,
          icon: Icons.check_circle_outline,
        );
      case StageOutcome.veto:
        return const StatusPill(label: 'DUMP-TRAP VETO', kind: SignalKind.veto, icon: Icons.gpp_maybe_outlined);
      case StageOutcome.fail:
        return const StatusPill(label: 'REJECTED', kind: SignalKind.fail, icon: Icons.cancel_outlined);
      case StageOutcome.pending:
        return const StatusPill(label: 'SCANNING', kind: SignalKind.pending, icon: Icons.hourglass_top);
    }
  }

  Widget _moduleRow() {
    return Row(
      children: [
        _moduleDot('M1', result.module1?.passed),
        _connector(result.module1 != null),
        _moduleDot('M2', result.module2?.passed),
        _connector(result.module2 != null),
        _moduleDot('M3', result.module3 == null ? null : (result.module3!.vetoed ? false : result.module3!.passed),
            veto: result.module3?.vetoed ?? false),
        _connector(result.module3 != null),
        _moduleDot('M4', result.module4?.passed),
      ],
    );
  }

  Widget _connector(bool reached) {
    return Expanded(
      child: Container(height: 2, color: reached ? AppColors.borderStrong : AppColors.borderSubtle),
    );
  }

  Widget _moduleDot(String label, bool? passed, {bool veto = false}) {
    Color color;
    if (passed == null) {
      color = AppColors.textTertiary;
    } else if (veto) {
      color = AppColors.signalVeto;
    } else {
      color = passed ? AppColors.signalPass : AppColors.signalFail;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(passed == null ? 0.08 : 0.18),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Icon(
            veto
                ? Icons.priority_high
                : (passed == null ? Icons.remove : (passed ? Icons.check : Icons.close)),
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: AppTheme.mono(size: 9, color: AppColors.textTertiary)),
      ],
    );
  }

  Widget _module2Detail(Module2Result m) {
    return _DetailPanel(
      title: 'MODULE 2 — PATTERN & CATALYST',
      children: [
        Row(
          children: [
            Expanded(
              child: MetricGauge(
                label: 'Base bandwidth',
                value: (m.bandwidth / 0.08),
                color: m.baseQualifies ? AppColors.signalPass : AppColors.signalFail,
                valueLabel: '${(m.bandwidth * 100).toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricGauge(
                label: 'Volume dry-up',
                value: m.volumeDryUp,
                color: m.baseQualifies ? AppColors.signalPass : AppColors.signalFail,
                valueLabel: '${(m.volumeDryUp * 100).toStringAsFixed(1)}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            StatusPill(
              label: m.breakoutQualifies ? '90D BREAKOUT ✓' : '90D BREAKOUT ✗',
              kind: m.breakoutQualifies ? SignalKind.pass : SignalKind.fail,
            ),
            StatusPill(
              label: 'UPSIDE ${(m.projectedUpsidePct * 100).toStringAsFixed(0)}%',
              kind: SignalKind.pending,
            ),
            if (m.blockedByPromptInjection)
              const StatusPill(label: 'INJECTION BLOCKED', kind: SignalKind.warn, icon: Icons.block),
            for (final tag in m.catalystTags)
              StatusPill(label: tag.replaceAll('_', ' ').toUpperCase(), kind: SignalKind.pass, icon: Icons.bolt),
          ],
        ),
        if (m.failReason != null) _failLine(m.failReason!),
      ],
    );
  }

  Widget _module3Detail(Module3Result m) {
    final upside = m.netExpectedEdgePct + m.effectiveFrictionTaxPct;
    return _DetailPanel(
      title: 'MODULE 3 — FRICTION BACKTEST',
      children: [
        MetricGauge(
          label: 'Synthetic ATR spread penalty (1.5x ATR_10)',
          value: upside == 0 ? 0 : (m.effectiveFrictionTaxPct / (upside == 0 ? 1 : upside)),
          color: AppColors.signalVeto,
          valueLabel: '${(m.effectiveFrictionTaxPct * 100).toStringAsFixed(1)}% friction',
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Net expected edge', style: AppTheme.mono(size: 11, color: AppColors.textSecondary)),
            Text(
              '${(m.netExpectedEdgePct * 100).toStringAsFixed(1)}%',
              style: AppTheme.mono(
                size: 13,
                weight: FontWeight.w800,
                color: m.netExpectedEdgePct >= 0.10 ? AppColors.signalPass : AppColors.signalFail,
              ),
            ),
          ],
        ),
        if (m.vetoed) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in m.vetoTags)
                StatusPill(label: tag.toUpperCase(), kind: SignalKind.veto, icon: Icons.gpp_maybe_outlined),
            ],
          ),
        ],
        if (m.failReason != null) _failLine(m.failReason!),
      ],
    );
  }

  Widget _module4Detail(Module4Result m) {
    return _DetailPanel(
      title: 'MODULE 4 — COMPLIANCE FIREWALL',
      children: [
        MetricGauge(
          label: 'Schedule 13D float cap utilization (4.9% ceiling)',
          value: m.schedule13dUtilizationPct,
          color: m.schedule13dUtilizationPct > 0.9 ? AppColors.signalWarn : AppColors.accentPrimary,
          valueLabel: '${(m.schedule13dUtilizationPct * 100).toStringAsFixed(1)}%',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _capLine('Risk', m.riskBasedShares)),
            Expanded(child: _capLine('Cash', m.cashCappedShares)),
            Expanded(child: _capLine('13D', m.max13dSafeShares)),
            Expanded(child: _capLine('Liquidity', m.maxLiquidityShares)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Approved shares', style: AppTheme.mono(size: 11, color: AppColors.textSecondary)),
            Text('${m.approvedShares}',
                style: AppTheme.mono(size: 14, weight: FontWeight.w800, color: AppColors.accentPrimary)),
          ],
        ),
        if (m.routedOrderId != null) ...[
          const SizedBox(height: 6),
          StatusPill(label: 'ROUTED ${m.routedOrderId}', kind: SignalKind.pass, icon: Icons.send),
        ],
        if (m.failReason != null) _failLine(m.failReason!),
      ],
    );
  }

  Widget _capLine(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.mono(size: 9, color: AppColors.textTertiary)),
        Text('$value', style: AppTheme.mono(size: 11, weight: FontWeight.w700)),
      ],
    );
  }

  Widget _failLine(String reason) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        reason,
        style: AppTheme.mono(size: 10.5, color: AppColors.textTertiary),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailPanel({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceRaised.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.mono(size: 10, weight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
