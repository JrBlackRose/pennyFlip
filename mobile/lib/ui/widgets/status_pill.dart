import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class StatusPill extends StatelessWidget {
  final String label;
  final SignalKind kind;
  final IconData? icon;

  const StatusPill({super.key, required this.label, required this.kind, this.icon});

  @override
  Widget build(BuildContext context) {
    final color = signalColor(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTheme.mono(size: 11, color: color, weight: FontWeight.w700, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

/// A thin horizontal gauge used for the Module 3 friction-vs-upside bar and
/// the Module 4 Schedule 13D utilization gauge.
class MetricGauge extends StatelessWidget {
  final String label;
  final double value; // 0..1, clamps
  final Color color;
  final String valueLabel;

  const MetricGauge({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTheme.mono(size: 11, color: AppColors.textSecondary)),
            Text(valueLabel, style: AppTheme.mono(size: 11, color: color, weight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: clamped,
            minHeight: 6,
            backgroundColor: AppColors.bgSurfaceRaised,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}
