import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class FunnelStageCount {
  final String label;
  final int count;
  final Color color;
  const FunnelStageCount({required this.label, required this.count, required this.color});
}

/// Pipeline Filter Funnel — spec UI requirement 3.b. Shows how many
/// candidates made it through each of the 4 modules this session, narrowing
/// left-to-right like a sales funnel.
class PipelineFunnel extends StatelessWidget {
  final int scanned;
  final int module1Pass;
  final int module2Pass;
  final int module3Pass;
  final int module3Veto;
  final int module4Approved;

  const PipelineFunnel({
    super.key,
    required this.scanned,
    required this.module1Pass,
    required this.module2Pass,
    required this.module3Pass,
    required this.module3Veto,
    required this.module4Approved,
  });

  @override
  Widget build(BuildContext context) {
    final stages = [
      FunnelStageCount(label: 'SCANNED', count: scanned, color: AppColors.signalPending),
      FunnelStageCount(label: 'MOD 1\nDATA', count: module1Pass, color: AppColors.textSecondary),
      FunnelStageCount(label: 'MOD 2\nPATTERN', count: module2Pass, color: AppColors.signalPass),
      FunnelStageCount(label: 'MOD 3\nBACKTEST', count: module3Pass, color: AppColors.signalPass),
      FunnelStageCount(label: 'MOD 4\nAPPROVED', count: module4Approved, color: AppColors.accentPrimary),
    ];
    final maxCount = scanned == 0 ? 1 : scanned;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('PIPELINE FILTER FUNNEL',
                    style: AppTheme.mono(size: 12, weight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.8)),
                if (module3Veto > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gpp_maybe, size: 14, color: AppColors.signalVeto),
                      const SizedBox(width: 4),
                      Text('$module3Veto VETOED',
                          style: AppTheme.mono(size: 11, color: AppColors.signalVeto, weight: FontWeight.w700)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 14),
            for (final s in stages) ...[
              _FunnelRow(stage: s, maxCount: maxCount),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  final FunnelStageCount stage;
  final int maxCount;
  const _FunnelRow({required this.stage, required this.maxCount});

  @override
  Widget build(BuildContext context) {
    final fraction = maxCount == 0 ? 0.0 : (stage.count / maxCount).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(stage.label, style: AppTheme.mono(size: 9, color: AppColors.textTertiary, weight: FontWeight.w700)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 20,
                decoration: BoxDecoration(color: AppColors.bgSurfaceRaised, borderRadius: BorderRadius.circular(4)),
              ),
              FractionallySizedBox(
                widthFactor: fraction == 0 ? 0.015 : fraction,
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(color: stage.color.withOpacity(0.75), borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '${stage.count}',
            textAlign: TextAlign.right,
            style: AppTheme.mono(size: 12, color: AppColors.textPrimary, weight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
