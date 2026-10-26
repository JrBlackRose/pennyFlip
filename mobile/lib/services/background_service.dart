import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'alarm_scheduler.dart';
import 'market_clock_service.dart';
import 'scan_orchestrator.dart';
import 'settings_service.dart';

/// pennyFlip's Android Foreground Service lifecycle (spec section 2).
///
/// Single state machine, entirely driven by MarketClockService:
///   - onStart (fired by the Exact Alarm at next_open, by BootReceiver, or
///     by a manual "Start now" tap) -> check the clock.
///       - is_open == true  -> become a foreground service, acquire a
///         partial WakeLock, post the persistent status notification, and
///         run scan cycles on a timer until market close.
///       - is_open == false -> re-schedule the next_open alarm and stop
///         immediately (handles a late/duplicate trigger gracefully).
///   - every scan tick -> re-check the clock; if it just closed, run the
///     clean teardown (spec section 2.3) and stop.
class BackgroundServiceController {
  BackgroundServiceController._();

  static const _notificationChannelId = 'pennyflip_sniper_channel';
  static const _notificationId = 888;
  static const _scanTickInterval = Duration(minutes: 5);

  static const String statusChannelEvent = 'pennyflip_status';

  /// Call once from main() before runApp().
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const androidNotificationChannel = AndroidNotificationChannel(
      _notificationChannelId,
      'pennyFlip Sniper',
      description: 'Market-hours scanning daemon status',
      importance: Importance.low, // low = no sound/heads-up, just a persistent status row
    );

    final notifications = FlutterLocalNotificationsPlugin();
    await notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidNotificationChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // we drive starts explicitly via Exact Alarms / BootReceiver, not plugin autostart
        isForegroundMode: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'pennyFlip',
        initialNotificationContent: 'Checking US market clock…',
        foregroundServiceNotificationId: _notificationId,
        // The dataSync foreground-service TYPE itself (spec requirement) is
        // declared natively in AndroidManifest.xml on the
        // id.flutter.flutter_background_service.BackgroundService <service>
        // entry (android:foregroundServiceType="dataSync"), which is the
        // part Android actually enforces at OS level and is stable across
        // plugin versions. We deliberately don't also pass a Dart-side
        // foregroundServiceTypes field here — that parameter's name/enum
        // has changed across flutter_background_service releases, and the
        // manifest declaration alone is sufficient to satisfy Android 14's
        // foreground-service-type requirement.
      ),
      iosConfiguration: IosConfiguration(autoStart: false, onForeground: onStart, onBackground: null),
    );
  }

  /// Entry point used by MainActivity / settings screen for a manual
  /// "Start scanning now" override.
  static Future<void> manualStart() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  static Future<void> manualStop() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
  }
}

/// Runs in the headless background isolate once the Foreground Service
/// starts. Must stay a top-level/static function annotated as a VM entry
/// point (same reasoning as the alarm callback).
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('stop').listen((event) async {
      await _teardown(service, reason: 'manual_stop');
    });
  }

  await _reconcileAndRun(service);
}

/// The single re-entrant decision point described in the class doc above.
Future<void> _reconcileAndRun(ServiceInstance service) async {
  final override = await SettingsService.instance.getDaemonManualOverride();
  if (override == 'force_off') {
    await _teardown(service, reason: 'manual_override_force_off');
    return;
  }

  final clock = await MarketClockService.instance.getSnapshot();
  final shouldRun = override == 'force_on' || clock.isOpen;

  if (!shouldRun) {
    // Market is closed: make sure the next wake alarm is registered, then
    // get out of the way completely (spec section 2.3 / 2.4).
    await AlarmScheduler.scheduleWakeAt(clock.nextOpenUtc);
    await _teardown(service, reason: 'market_closed', nextOpenUtc: clock.nextOpenUtc);
    return;
  }

  // Market is open (or manually forced on): become the persistent
  // foreground scanner.
  await WakelockPlus.enable();
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'pennyFlip Sniper Active',
      content: 'US Market Open | Scanning EDGAR & Microcaps',
    );
  }

  _emitStatus(service, isActive: true, clock: clock, lastTick: DateTime.now());

  Timer.periodic(BackgroundServiceController._scanTickInterval, (timer) async {
    final latestOverride = await SettingsService.instance.getDaemonManualOverride();
    if (latestOverride == 'force_off') {
      timer.cancel();
      await _teardown(service, reason: 'manual_override_force_off');
      return;
    }

    final latestClock =
        latestOverride == 'force_on' ? clock : await MarketClockService.instance.getSnapshot();

    if (latestOverride != 'force_on' && !latestClock.isOpen) {
      // Market closed since the last tick -> run the clean teardown.
      timer.cancel();
      await AlarmScheduler.scheduleWakeAt(latestClock.nextOpenUtc);
      await _teardown(service, reason: 'market_closed', nextOpenUtc: latestClock.nextOpenUtc);
      return;
    }

    try {
      final summary = await ScanOrchestrator.instance.runCycle(trigger: 'background_tick');
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'pennyFlip Sniper Active',
          content: 'US Market Open | Scanned ${summary.scanned} • Approved ${summary.approved}',
        );
      }
    } catch (_) {
      // Swallow scan-cycle errors so one bad tick never kills the daemon;
      // the next tick (5 min later) tries again.
    }

    _emitStatus(service, isActive: true, clock: latestClock, lastTick: DateTime.now());
  });
}

/// Clean shutdown per spec section 2.3:
///   1. Verify/log any open paper orders (handled per-order as they route;
///      nothing additional to flush here since orders_log writes happen
///      synchronously during the scan cycle).
///   2./3. The next_open alarm is scheduled by the caller before teardown
///      is invoked (so a crash mid-teardown can't leave zero alarms armed).
///   4. Release the WakeLock and stop the Foreground Service so battery
///      consumption drops to 0% overnight.
Future<void> _teardown(ServiceInstance service,
    {required String reason, DateTime? nextOpenUtc}) async {
  await WakelockPlus.disable();
  _emitStatus(service, isActive: false, nextOpenUtc: nextOpenUtc, lastTick: DateTime.now());
  if (service is AndroidServiceInstance) {
    service.stopSelf();
  }
}

void _emitStatus(
  ServiceInstance service, {
  required bool isActive,
  MarketClockSnapshot? clock,
  DateTime? nextOpenUtc,
  required DateTime lastTick,
}) {
  service.invoke(BackgroundServiceController.statusChannelEvent, {
    'is_active': isActive,
    'next_open_utc': (clock?.nextOpenUtc ?? nextOpenUtc)?.toIso8601String(),
    'next_close_utc': clock?.nextCloseUtc.toIso8601String(),
    'last_tick_utc': lastTick.toUtc().toIso8601String(),
    'clock_source': clock?.source.name,
  });
}
