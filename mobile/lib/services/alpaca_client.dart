import 'dart:convert';
import 'package:http/http.dart' as http;

import 'settings_service.dart';

class AlpacaClock {
  final bool isOpen;
  final DateTime timestamp;
  final DateTime nextOpen;
  final DateTime nextClose;

  const AlpacaClock({
    required this.isOpen,
    required this.timestamp,
    required this.nextOpen,
    required this.nextClose,
  });

  factory AlpacaClock.fromJson(Map<String, dynamic> j) => AlpacaClock(
        isOpen: j['is_open'] as bool,
        timestamp: DateTime.parse(j['timestamp'] as String),
        nextOpen: DateTime.parse(j['next_open'] as String),
        nextClose: DateTime.parse(j['next_close'] as String),
      );
}

class AlpacaAsset {
  final String symbol;
  final String status;
  final bool tradable;
  final String exchange;

  const AlpacaAsset({
    required this.symbol,
    required this.status,
    required this.tradable,
    required this.exchange,
  });

  factory AlpacaAsset.fromJson(Map<String, dynamic> j) => AlpacaAsset(
        symbol: j['symbol'] as String,
        status: j['status'] as String,
        tradable: j['tradable'] as bool? ?? false,
        exchange: j['exchange'] as String? ?? '',
      );

  /// Phase 0 gate: reject if not active, not tradable, or OTC.
  bool get passesPhase0Gate => status == 'active' && tradable && exchange != 'OTC';
}

class AlpacaOrderResult {
  final String? id;
  final String status;
  final String? rejectReason;

  const AlpacaOrderResult({this.id, required this.status, this.rejectReason});
}

/// Thin client for the Alpaca Paper Trading API. Paper trading only — no
/// live-money endpoints are referenced anywhere in this app, matching the
/// spec's `paper-api.alpaca.markets` base URL throughout.
class AlpacaClient {
  AlpacaClient._internal();
  static final AlpacaClient instance = AlpacaClient._internal();

  static const _baseUrl = 'https://paper-api.alpaca.markets';

  Future<Map<String, String>> _headers() async {
    final keyId = await SettingsService.instance.getAlpacaApiKeyId();
    final secret = await SettingsService.instance.getAlpacaApiSecret();
    return {
      'APCA-API-KEY-ID': keyId ?? '',
      'APCA-API-SECRET-KEY': secret ?? '',
      'Content-Type': 'application/json',
    };
  }

  /// GET /v2/clock — primary market-hours source of truth. Automatically
  /// reflects DST transitions and NYSE holidays.
  Future<AlpacaClock> getClock() async {
    final resp = await http.get(Uri.parse('$_baseUrl/v2/clock'), headers: await _headers());
    if (resp.statusCode != 200) {
      throw AlpacaException('GET /v2/clock failed: ${resp.statusCode} ${resp.body}');
    }
    return AlpacaClock.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// GET /v2/assets/{symbol} — Phase 0 interrogation gate.
  Future<AlpacaAsset?> getAsset(String symbol) async {
    final resp =
        await http.get(Uri.parse('$_baseUrl/v2/assets/$symbol'), headers: await _headers());
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw AlpacaException('GET /v2/assets/$symbol failed: ${resp.statusCode} ${resp.body}');
    }
    return AlpacaAsset.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// POST /v2/orders with a day LIMIT order, then DELETE /v2/orders/{id} —
  /// Phase 0's "simulated order" venue-restriction probe. Returns true if no
  /// "Restricted Venue" style rejection occurred.
  Future<bool> probeOrderRouting(String symbol, double limitPrice) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/v2/orders'),
      headers: await _headers(),
      body: jsonEncode({
        'symbol': symbol,
        'qty': '1',
        'side': 'buy',
        'type': 'limit',
        'limit_price': limitPrice.toStringAsFixed(2),
        'time_in_force': 'day',
        'extended_hours': false,
      }),
    );

    if (resp.statusCode == 403 || resp.body.contains('Restricted Venue')) {
      return false;
    }
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw AlpacaException('Order probe failed: ${resp.statusCode} ${resp.body}');
    }

    final id = (jsonDecode(resp.body) as Map<String, dynamic>)['id'] as String?;
    if (id != null) {
      await http.delete(Uri.parse('$_baseUrl/v2/orders/$id'), headers: await _headers());
    }
    return true;
  }

  /// POST /v2/orders — final Module 4 routing. Always a day LIMIT order with
  /// extended_hours disabled, per spec.
  Future<AlpacaOrderResult> routeLimitOrder({
    required String symbol,
    required int shares,
    required double limitPrice,
    required String side, // 'buy'
  }) async {
    final resp = await http.post(
      Uri.parse('$_baseUrl/v2/orders'),
      headers: await _headers(),
      body: jsonEncode({
        'symbol': symbol,
        'qty': shares.toString(),
        'side': side,
        'type': 'limit',
        'limit_price': limitPrice.toStringAsFixed(2),
        'time_in_force': 'day',
        'extended_hours': false,
      }),
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      return AlpacaOrderResult(status: 'rejected', rejectReason: '${resp.statusCode} ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return AlpacaOrderResult(id: body['id'] as String?, status: body['status'] as String? ?? 'submitted');
  }

  /// GET /v2/account — settled cash, used by Module 4 position sizing.
  Future<double> getSettledCash() async {
    final resp = await http.get(Uri.parse('$_baseUrl/v2/account'), headers: await _headers());
    if (resp.statusCode != 200) {
      throw AlpacaException('GET /v2/account failed: ${resp.statusCode} ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return double.tryParse(body['cash'] as String? ?? '0') ?? 0.0;
  }

  /// GET /v2/stocks/{symbol}/bars — raw, unadjusted daily bars (data API host).
  Future<List<Map<String, dynamic>>> getRawDailyBars(String symbol, {int limit = 120}) async {
    final uri = Uri.parse(
      'https://data.alpaca.markets/v2/stocks/$symbol/bars'
      '?timeframe=1Day&adjustment=raw&feed=iex&limit=$limit',
    );
    final resp = await http.get(uri, headers: await _headers());
    if (resp.statusCode != 200) {
      throw AlpacaException('GET bars failed for $symbol: ${resp.statusCode} ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['bars'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  /// GET /v2/account — full account map (cash, equity, last_equity) for drawdown guard.
  Future<Map<String, dynamic>> getAccountSummary() async {
    final resp = await http.get(Uri.parse('$_baseUrl/v2/account'), headers: await _headers());
    if (resp.statusCode != 200) {
      throw AlpacaException('GET /v2/account failed: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// GET /v2/positions — list all open paper positions.
  Future<List<Map<String, dynamic>>> getOpenPositions() async {
    final resp = await http.get(Uri.parse('$_baseUrl/v2/positions'), headers: await _headers());
    if (resp.statusCode != 200) {
      throw AlpacaException('GET /v2/positions failed: ${resp.statusCode} ${resp.body}');
    }
    return (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
  }

  /// DELETE /v2/positions/{symbol} — immediately market-close a single losing position.
  Future<void> closePosition(String symbol) async {
    await http.delete(Uri.parse('$_baseUrl/v2/positions/$symbol'), headers: await _headers());
  }

  /// DELETE /v2/orders — cancel all open working orders.
  Future<void> cancelAllOrders() async {
    await http.delete(Uri.parse('$_baseUrl/v2/orders'), headers: await _headers());
  }

  /// DELETE /v2/positions?cancel_orders=true — atomic Alpaca panic liquidation.
  Future<int> liquidateAllPositionsAndCancelOrders() async {
    final resp = await http.delete(
      Uri.parse('$_baseUrl/v2/positions?cancel_orders=true'),
      headers: await _headers(),
    );
    if (resp.statusCode != 200 && resp.statusCode != 207 && resp.statusCode != 204) {
      throw AlpacaException('Emergency liquidation failed: ${resp.statusCode} ${resp.body}');
    }
    if (resp.body.isEmpty) return 0;
    final decoded = jsonDecode(resp.body);
    return decoded is List ? decoded.length : 0;
  }
}

class AlpacaException implements Exception {
  final String message;
  AlpacaException(this.message);
  @override
  String toString() => 'AlpacaException: $message';
}
