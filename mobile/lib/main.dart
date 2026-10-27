import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/alarm_scheduler.dart';
import 'services/background_service.dart';
import 'services/market_clock_service.dart';
import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'ui/screens/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local notifications (used by flutter_background_service's persistent
  // status notification during market hours).
  if (Platform.isAndroid) {
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
  }

  // Android 13+ (API 33) requires a runtime grant for POST_NOTIFICATIONS, or
  // the Foreground Service still runs but its persistent status notification
  // (spec requirement: "pennyFlip Sniper Active | US Market Open…") won't
  // actually display. SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM are handled
  // purely via the manifest — this app's whole purpose is exact-alarm-driven
  // scheduling, so USE_EXACT_ALARM is auto-granted on API 33+ without a
  // settings round-trip.
  if (Platform.isAndroid) {
    await Permission.notification.request();
  }

  // Wire up the Foreground Service lifecycle (spec section 2).
  await BackgroundServiceController.initialize();
  await AlarmScheduler.ensureInitialized();

  // On a cold app launch (not a boot/alarm headless launch), reconcile the
  // wake-alarm schedule against the current market clock so a fresh install
  // or a long-dead app immediately has a correct next_open alarm armed,
  // without waiting for the user to open Settings.
  await _reconcileWakeAlarmOnLaunch();

  runApp(const PennyFlipApp());
}

Future<void> _reconcileWakeAlarmOnLaunch() async {
  try {
    final override = await SettingsService.instance.getDaemonManualOverride();
    if (override == 'force_off') return;

    final snapshot = await MarketClockService.instance.getSnapshot();
    if (override == 'force_on' || !snapshot.isOpen) {
      // If forced on, the dashboard's "Start now" / force-on flow actually
      // starts the service; here we only make sure a wake alarm exists so
      // the device isn't left with zero scheduled wakeups if the user force
      // -on's and then later clears the override while the market is shut.
      await AlarmScheduler.scheduleWakeAt(snapshot.nextOpenUtc);
    }
  } catch (_) {
    // No network on cold launch (e.g. airplane mode) — the local fallback
    // inside MarketClockService already covers this; a genuine failure here
    // just means the user opens Settings, which re-triggers a clock check.
  }
}

class PennyFlipApp extends StatelessWidget {
  const PennyFlipApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pennyFlip',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const DashboardScreen(),
    );
  }
}
