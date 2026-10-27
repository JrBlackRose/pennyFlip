import '../db/app_database.dart';
import 'alpaca_client.dart';
import 'background_service.dart';
import 'settings_service.dart';

class KillSwitchReport {
  final bool triggered;
  final int positionsClosed;
  final List<String> actions;

  const KillSwitchReport({
    required this.triggered,
    required this.positionsClosed,
    required this.actions,
  });
}

/// Dual-Layer Killswitch & Automated Stop-Loss / Drawdown Firewall:
///   1. Automated Guard (`monitorActiveTrades`): Runs on every background tick.
///      - Closes any individual position that breaches its SQLite stop_loss_price
///        or drops <= -5.0% (`_maxPositionLossPct`).
///      - Triggers a full account liquidation + daemon lock if daily account equity
///        drawdown breaches <= -3.0% (`_maxDailyDrawdownPct`).
///   2. 1-Tap Emergency Panic Button (`triggerEmergencyPanic`):
///      - Forces daemon override to 'force_off', stops background scanner,
///        cancels all open orders, and liquidates all open positions on Alpaca.
class KillSwitchService {
  KillSwitchService._();

  static const double _maxPositionLossPct = -0.05; // -5% hard stop per trade
  static const double _maxDailyDrawdownPct = -0.03; // -3% max daily account drawdown

  static Future<KillSwitchReport> triggerEmergencyPanic({String reason = 'MANUAL_PANIC_BUTTON'}) async {
    final actions = <String>[];
    await SettingsService.instance.setDaemonManualOverride('force_off');
    await BackgroundServiceController.manualStop();
    actions.add('Daemon locked to FORCED OFF ($reason)');

    var closedCount = 0;
    if (await SettingsService.instance.hasCredentials()) {
      try {
        await AlpacaClient.instance.cancelAllOrders();
        actions.add('Cancelled all open working orders');
      } catch (e) {
        actions.add('Cancel orders error: $e');
      }
      try {
        closedCount = await AlpacaClient.instance.liquidateAllPositionsAndCancelOrders();
        actions.add('Liquidated $closedCount open position(s) at market');
      } catch (e) {
        actions.add('Liquidation error: $e');
      }
    } else {
      actions.add('No Alpaca credentials configured — local daemon halted only');
    }

    await AppDatabase.instance.logOrder(
      cik10: '0000000000',
      ticker: 'KILLSWITCH',
      approvedShares: closedCount,
      limitPrice: 0,
      status: 'KILLSWITCH:$reason',
      createdAt: DateTime.now(),
    );

    return KillSwitchReport(
      triggered: true,
      positionsClosed: closedCount,
      actions: actions,
    );
  }

  /// Automatically called on every background tick before scanning new candidates.
  static Future<KillSwitchReport> monitorActiveTrades() async {
    if (!await SettingsService.instance.hasCredentials()) {
      return const KillSwitchReport(triggered: false, positionsClosed: 0, actions: []);
    }

    final actions = <String>[];
    var closedCount = 0;

    // 1. Check account-level daily drawdown (-3% circuit breaker)
    try {
      final acct = await AlpacaClient.instance.getAccountSummary();
      final equity = double.tryParse(acct['equity']?.toString() ?? '0') ?? 0;
      final lastEquity = double.tryParse(acct['last_equity']?.toString() ?? '0') ?? 0;
      if (lastEquity > 0) {
        final dailyReturn = (equity - lastEquity) / lastEquity;
        if (dailyReturn <= _maxDailyDrawdownPct) {
          return await triggerEmergencyPanic(
            reason: 'DAILY_DRAWDOWN_${(dailyReturn * 100).toStringAsFixed(1)}%',
          );
        }
      }
    } catch (_) {}

    // 2. Check individual open positions against logged stop-loss & -5% hard stop
    try {
      final positions = await AlpacaClient.instance.getOpenPositions();
      final recentOrders = await AppDatabase.instance.recentOrders(limit: 50);

      for (final pos in positions) {
        final symbol = (pos['symbol'] as String? ?? '').toUpperCase();
        final currentPrice = double.tryParse(pos['current_price']?.toString() ?? '0') ?? 0;
        final unrealizedPlpc = double.tryParse(pos['unrealized_plpc']?.toString() ?? '0') ?? 0;

        double? loggedStop;
        for (final row in recentOrders) {
          if ((row['ticker'] as String? ?? '').toUpperCase() == symbol && row['stop_loss_price'] != null) {
            loggedStop = (row['stop_loss_price'] as num).toDouble();
            break;
          }
        }

        final hitLoggedStop = loggedStop != null && currentPrice > 0 && currentPrice <= loggedStop;
        final hitHardPctStop = unrealizedPlpc <= _maxPositionLossPct;

        if (hitLoggedStop || hitHardPctStop) {
          await AlpacaClient.instance.closePosition(symbol);
          closedCount++;
          final why = hitLoggedStop
              ? 'price $currentPrice <= stop $loggedStop'
              : 'PnL ${(unrealizedPlpc * 100).toStringAsFixed(1)}% <= -5.0%';
          actions.add('Auto-liquidated $symbol ($why)');
          await AppDatabase.instance.logOrder(
            cik10: '0000000000',
            ticker: symbol,
            approvedShares: 0,
            limitPrice: currentPrice,
            stopLossPrice: loggedStop,
            status: 'AUTO_STOP_OUT:$why',
            createdAt: DateTime.now(),
          );
        }
      }
    } catch (_) {}

    return KillSwitchReport(
      triggered: closedCount > 0,
      positionsClosed: closedCount,
      actions: actions,
    );
  }
}
