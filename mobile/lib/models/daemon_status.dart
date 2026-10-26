/// UI-facing snapshot of the background daemon, assembled from either the
/// running Foreground Service's status broadcast (service.on(statusEvent))
/// or a direct MarketClockService.getSnapshot() call when the service isn't
/// currently running.
class DaemonStatus {
  final bool isActive;
  final DateTime? nextOpenUtc;
  final DateTime? nextCloseUtc;
  final DateTime? lastTickUtc;
  final String? clockSource; // 'alpaca' | 'localFallback'
  final String? manualOverride; // null | 'force_on' | 'force_off'

  const DaemonStatus({
    required this.isActive,
    this.nextOpenUtc,
    this.nextCloseUtc,
    this.lastTickUtc,
    this.clockSource,
    this.manualOverride,
  });

  DaemonStatus copyWith({
    bool? isActive,
    DateTime? nextOpenUtc,
    DateTime? nextCloseUtc,
    DateTime? lastTickUtc,
    String? clockSource,
    String? manualOverride,
    bool clearManualOverride = false,
  }) {
    return DaemonStatus(
      isActive: isActive ?? this.isActive,
      nextOpenUtc: nextOpenUtc ?? this.nextOpenUtc,
      nextCloseUtc: nextCloseUtc ?? this.nextCloseUtc,
      lastTickUtc: lastTickUtc ?? this.lastTickUtc,
      clockSource: clockSource ?? this.clockSource,
      manualOverride: clearManualOverride ? null : (manualOverride ?? this.manualOverride),
    );
  }

  static const initial = DaemonStatus(isActive: false);
}
