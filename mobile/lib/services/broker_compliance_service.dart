import 'dart:math';

import '../models/pipeline_result.dart';
import 'alpaca_client.dart';

/// Phase 0 (Broker API Interrogation Gate) + Module 4 (Broker Execution &
/// Compliance Firewall).
class BrokerComplianceService {
  BrokerComplianceService._();

  static const _riskPerTradePct = 0.02; // 2% of settled cash
  static const _cashCapPct = 0.95; // never deploy more than 95% of settled cash
  static const _schedule13dCapPct = 0.049; // stay under the 5.0% disclosure threshold
  static const _liquidityCapPct = 0.05; // never exceed 5% of 20d avg daily volume

  /// Phase 0 gate. Returns null if the asset passes; returns a reason string
  /// if it should be rejected before any capital is risked probing further.
  static Future<String?> phase0Gate(String symbol, {double? probeLimitPrice}) async {
    final asset = await AlpacaClient.instance.getAsset(symbol);
    if (asset == null) {
      return 'Asset $symbol not found on broker';
    }
    if (asset.status != 'active') {
      return 'Asset status is "${asset.status}", not "active"';
    }
    if (!asset.tradable) {
      return 'Asset is not tradable on this broker';
    }
    if (asset.exchange == 'OTC') {
      return 'Asset trades on OTC — rejected per spec Phase 0 gate';
    }

    if (probeLimitPrice != null) {
      try {
        final routingOk = await AlpacaClient.instance.probeOrderRouting(symbol, probeLimitPrice);
        if (!routingOk) {
          return 'Simulated limit order probe returned a Restricted Venue error';
        }
      } on AlpacaException catch (e) {
        return 'Order routing probe failed: $e';
      }
    }

    return null; // passes
  }

  /// Pure Module 4 position-sizing math — no network, no async. Exposed on
  /// its own so the on-device self-test harness can exercise the exact
  /// `approved_shares = min(...)` formula offline. This is also the first
  /// half of [evaluateAndRoute] below.
  static Module4Result sizePosition({
    required double settledCash,
    required double entryPrice,
    required double stopLossPrice,
    required double sharesOutstanding,
    required double avgDailyVolume20d,
  }) {
    final riskPerShare = entryPrice - stopLossPrice;
    final riskBasedShares = riskPerShare <= 0
        ? 0
        : ((settledCash * _riskPerTradePct) / riskPerShare).floor();

    final cashCappedShares = entryPrice <= 0 ? 0 : ((settledCash * _cashCapPct) / entryPrice).floor();

    final max13dSafeShares = (sharesOutstanding * _schedule13dCapPct).floor();

    final maxLiquidityShares = (avgDailyVolume20d * _liquidityCapPct).floor();

    final approvedShares = [
      riskBasedShares,
      cashCappedShares,
      max13dSafeShares,
      maxLiquidityShares,
    ].reduce(min);

    final utilizationPct = max13dSafeShares == 0 ? 0.0 : approvedShares / max13dSafeShares;

    return Module4Result(
      passed: approvedShares > 0,
      riskBasedShares: riskBasedShares,
      cashCappedShares: cashCappedShares,
      max13dSafeShares: max13dSafeShares,
      maxLiquidityShares: maxLiquidityShares,
      approvedShares: approvedShares > 0 ? approvedShares : 0,
      schedule13dUtilizationPct: utilizationPct,
      failReason: approvedShares > 0
          ? null
          : 'All sizing caps resolved to 0 approved shares '
              '(risk=$riskBasedShares, cash=$cashCappedShares, '
              '13d=$max13dSafeShares, liquidity=$maxLiquidityShares)',
    );
  }

  /// Module 4 position sizing + order routing for one approved candidate.
  /// Sizing is synchronous (see [sizePosition]); routing only happens, and
  /// only awaits the network, when [autoTradeEnabled] is true and sizing
  /// produced a positive share count.
  static Future<Module4Result> evaluateAndRoute({
    required String symbol,
    required double settledCash,
    required double entryPrice,
    required double stopLossPrice,
    required double sharesOutstanding,
    required double avgDailyVolume20d,
    required bool autoTradeEnabled,
  }) async {
    final sized = sizePosition(
      settledCash: settledCash,
      entryPrice: entryPrice,
      stopLossPrice: stopLossPrice,
      sharesOutstanding: sharesOutstanding,
      avgDailyVolume20d: avgDailyVolume20d,
    );

    if (sized.approvedShares <= 0 || !autoTradeEnabled) {
      // Either nothing to size, or sized-but-not-routed (manual-confirm
      // mode: routedOrderId stays null).
      return sized;
    }

    final orderResult = await AlpacaClient.instance.routeLimitOrder(
      symbol: symbol,
      shares: sized.approvedShares,
      limitPrice: entryPrice,
      side: 'buy',
    );

    return Module4Result(
      passed: orderResult.status != 'rejected',
      riskBasedShares: sized.riskBasedShares,
      cashCappedShares: sized.cashCappedShares,
      max13dSafeShares: sized.max13dSafeShares,
      maxLiquidityShares: sized.maxLiquidityShares,
      approvedShares: sized.approvedShares,
      schedule13dUtilizationPct: sized.schedule13dUtilizationPct,
      routedOrderId: orderResult.id,
      failReason: orderResult.status == 'rejected' ? orderResult.rejectReason : null,
    );
  }
}
