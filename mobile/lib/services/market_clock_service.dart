import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'alpaca_client.dart';

enum ClockSource { alpaca, localFallback }

class MarketClockSnapshot {
  final bool isOpen;
  final DateTime nextOpenUtc;
  final DateTime nextCloseUtc;
  final ClockSource source;
  final DateTime evaluatedAtUtc;

  const MarketClockSnapshot({
    required this.isOpen,
    required this.nextOpenUtc,
    required this.nextCloseUtc,
    required this.source,
    required this.evaluatedAtUtc,
  });
}

/// Dual-clock synchronization (spec section 2.1):
///   1. Primary: Alpaca GET /v2/clock — automatically accounts for US DST
///      transitions and NYSE holidays.
///   2. Fallback: local America/New_York timezone conversion, 09:30–16:00,
///      Monday–Friday, used only when the Alpaca call fails (no network,
///      bad credentials, Alpaca outage) so the background daemon can still
///      make a reasonable wake/sleep decision.
class MarketClockService {
  MarketClockService._internal();
  static final MarketClockService instance = MarketClockService._internal();

  bool _tzInitialized = false;

  Future<void> _ensureTz() async {
    if (_tzInitialized) return;
    tzdata.initializeTimeZones();
    _tzInitialized = true;
  }

  Future<MarketClockSnapshot> getSnapshot() async {
    try {
      final clock = await AlpacaClient.instance.getClock();
      return MarketClockSnapshot(
        isOpen: clock.isOpen,
        nextOpenUtc: clock.nextOpen.toUtc(),
        nextCloseUtc: clock.nextClose.toUtc(),
        source: ClockSource.alpaca,
        evaluatedAtUtc: DateTime.now().toUtc(),
      );
    } catch (_) {
      return _localFallback();
    }
  }

  /// Local timezone fallback. Computes "is the market open right now" using
  /// a plain 09:30–16:00 America/New_York, Mon–Fri rule (no holiday
  /// calendar — that's the one thing only Alpaca's /v2/clock truly knows).
  Future<MarketClockSnapshot> _localFallback() async {
    await _ensureTz();
    final ny = tz.getLocation('America/New_York');
    final nowNy = tz.TZDateTime.now(ny);

    bool isWeekday(tz.TZDateTime d) => d.weekday >= DateTime.monday && d.weekday <= DateTime.friday;

    final todayOpen = tz.TZDateTime(ny, nowNy.year, nowNy.month, nowNy.day, 9, 30);
    final todayClose = tz.TZDateTime(ny, nowNy.year, nowNy.month, nowNy.day, 16, 0);

    final isOpen = isWeekday(nowNy) && !nowNy.isBefore(todayOpen) && nowNy.isBefore(todayClose);

    // Compute next_open: if before today's open on a weekday -> today's
    // open; otherwise -> the next weekday's 09:30.
    tz.TZDateTime nextOpen;
    if (isWeekday(nowNy) && nowNy.isBefore(todayOpen)) {
      nextOpen = todayOpen;
    } else {
      var candidate = tz.TZDateTime(ny, nowNy.year, nowNy.month, nowNy.day + 1, 9, 30);
      while (!isWeekday(candidate)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      nextOpen = candidate;
    }

    // Compute next_close: if currently open -> today's close; otherwise the
    // close on the same trading day as nextOpen.
    final nextClose = isOpen
        ? todayClose
        : tz.TZDateTime(ny, nextOpen.year, nextOpen.month, nextOpen.day, 16, 0);

    return MarketClockSnapshot(
      isOpen: isOpen,
      nextOpenUtc: nextOpen.toUtc(),
      nextCloseUtc: nextClose.toUtc(),
      source: ClockSource.localFallback,
      evaluatedAtUtc: DateTime.now().toUtc(),
    );
  }
}
