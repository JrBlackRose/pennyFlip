import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/daemon_status.dart';
import '../../theme/app_theme.dart';
import 'status_pill.dart';

class MarketClockBanner extends StatefulWidget {
  final DaemonStatus status;
  final VoidCallback onStartNow;
  final VoidCallback onStopNow;
  final ValueChanged<bool> onForceOverrideChanged; // true = force on, false = clear/force off toggle handled by parent

  const MarketClockBanner({
    super.key,
    required this.status,
    required this.onStartNow,
    required this.onStopNow,
    required this.onForceOverrideChanged,
  });

  @override
  State<MarketClockBanner> createState() => _MarketClockBannerState();
}

class _MarketClockBannerState extends State<MarketClockBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _countdown(DateTime targetUtc) {
    final diff = targetUtc.difference(DateTime.now().toUtc());
    if (diff.isNegative) return '00:00:00';
    final h = diff.inHours.toString().padLeft(2, '0');
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final isActive = status.isActive;
    final target = isActive ? status.nextCloseUtc : status.nextOpenUtc;
    final targetLabel = isActive ? 'Hibernates in' : 'Wakes in';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isActive
              ? [AppColors.accentDim.withOpacity(0.22), AppColors.bgSurface]
              : [AppColors.bgSurfaceRaised, AppColors.bgSurface],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? AppColors.accentPrimary.withOpacity(0.5) : AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _HeartbeatDot(isActive: isActive),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isActive ? 'DAEMON ACTIVE — US MARKET OPEN' : 'DAEMON HIBERNATING — MARKET CLOSED',
                  style: AppTheme.mono(
                    size: 13,
                    weight: FontWeight.w800,
                    color: isActive ? AppColors.accentPrimary : AppColors.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (status.manualOverride != null)
                StatusPill(
                  label: status.manualOverride == 'force_on' ? 'FORCED ON' : 'FORCED OFF',
                  kind: SignalKind.warn,
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (target != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _countdown(target),
                  style: AppTheme.mono(size: 30, weight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(targetLabel, style: AppTheme.mono(size: 12, color: AppColors.textSecondary)),
                ),
              ],
            )
          else
            Text('Clock not yet synced', style: AppTheme.mono(size: 13, color: AppColors.textTertiary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _InfoLine(
                  label: 'Source',
                  value: status.clockSource == 'alpaca' ? 'Alpaca /v2/clock' : 'Local NY fallback'),
              _InfoLine(
                  label: 'Last tick',
                  value: status.lastTickUtc != null ? _fmtTime(status.lastTickUtc!) : '—'),
              _InfoLine(
                  label: 'Next open',
                  value: status.nextOpenUtc != null ? _fmtTime(status.nextOpenUtc!) : '—'),
              _InfoLine(
                  label: 'Next close',
                  value: status.nextCloseUtc != null ? _fmtTime(status.nextCloseUtc!) : '—'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isActive ? widget.onStopNow : widget.onStartNow,
                  icon: Icon(isActive ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 18),
                  label: Text(isActive ? 'Stop now' : 'Start now'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: status.manualOverride == null ? 'Manual override' : 'Clear override',
                onPressed: () => widget.onForceOverrideChanged(status.manualOverride == null),
                icon: Icon(
                  status.manualOverride == null ? Icons.lock_open : Icons.lock,
                  color: status.manualOverride == null ? AppColors.textSecondary : AppColors.signalWarn,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtTime(DateTime utc) {
    final local = utc.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm local';
  }
}

class _HeartbeatDot extends StatefulWidget {
  final bool isActive;
  const _HeartbeatDot({required this.isActive});

  @override
  State<_HeartbeatDot> createState() => _HeartbeatDotState();
}

class _HeartbeatDotState extends State<_HeartbeatDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive ? AppColors.accentPrimary : AppColors.textTertiary;
    if (!widget.isActive) {
      return Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(0.6 * (1 - t)), blurRadius: 10 * t, spreadRadius: 4 * t)],
          ),
        );
      },
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: '$label  ', style: AppTheme.mono(size: 11, color: AppColors.textTertiary)),
          TextSpan(text: value, style: AppTheme.mono(size: 11, color: AppColors.textPrimary, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
