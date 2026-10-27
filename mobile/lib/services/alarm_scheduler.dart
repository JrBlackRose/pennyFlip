import 'dart:io' show Platform;
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// Exact-alarm scheduling for the market-hours wake/sleep cycle
/// (spec section 2.2 & 2.3).
///
/// Only one alarm is ever outstanding: either "wake at next_open" (while the
/// market is closed) or nothing (while the market is open and the Foreground
/// Service itself is responsible for tearing down and re-scheduling at
/// next_close). This keeps the wake/sleep state machine simple and avoids
/// duplicate/overlapping alarms.
class AlarmScheduler {
  AlarmScheduler._();

  /// A fixed, well-known alarm id for the single "wake at next_open" alarm.
  static const int wakeAlarmId = 0x70464C50; // 'pFLP' as hex, arbitrary constant

  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized || !Platform.isAndroid) return;
    await AndroidAlarmManager.initialize();
    _initialized = true;
  }

  /// Schedules (or replaces) the Exact Alarm that fires at [nextOpenUtc].
  /// `rescheduleOnReboot: true` means the plugin itself re-registers this
  /// alarm with Android's AlarmManager if the device reboots before it
  /// fires — part of the boot-persistence story alongside BootReceiver.
  static Future<void> scheduleWakeAt(DateTime nextOpenUtc) async {
    if (!Platform.isAndroid) return;
    await ensureInitialized();
    await AndroidAlarmManager.cancel(wakeAlarmId);
    await AndroidAlarmManager.oneShotAt(
      nextOpenUtc.toLocal(),
      wakeAlarmId,
      marketOpenAlarmCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true, // AlarmManager.setExactAndAllowWhileIdle per spec, fires even in deep Doze
      rescheduleOnReboot: true,
      alarmClock: true, // highest-priority alarm type; survives aggressive OEM Doze variants
    );
  }

  static Future<void> cancelWakeAlarm() async {
    if (!Platform.isAndroid) return;
    await ensureInitialized();
    await AndroidAlarmManager.cancel(wakeAlarmId);
  }
}

/// Fired by AlarmManager at (approximately) US market open. Must be a
/// top-level function marked as a VM entry point so it can be found from the
/// headless alarm-manager isolate.
///
/// This callback does the minimum possible: it starts
/// `flutter_background_service`'s Foreground Service. All of the "is the
/// market actually open right now" re-verification happens inside that
/// service's onStart handler (see background_service.dart), which queries
/// /v2/clock itself before doing anything else — so a slightly-early/late
/// alarm firing, a missed DST transition, or a market holiday are all
/// self-corrected in one place rather than duplicated here.
@pragma('vm:entry-point')
void marketOpenAlarmCallback() async {
  DartPluginRegistrant.ensureInitialized();
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  }
}
