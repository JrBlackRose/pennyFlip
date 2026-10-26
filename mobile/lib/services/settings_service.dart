import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure, on-device storage for the Alpaca Paper API credentials and SEC
/// User-Agent string (spec section 3.c "Settings screen"). Backed by Android
/// Keystore via flutter_secure_storage — nothing here ever leaves the
/// device, and nothing is written to the SQLite database.
class SettingsService {
  SettingsService._internal();
  static final SettingsService instance = SettingsService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyApiKeyId = 'alpaca_api_key_id';
  static const _keyApiSecret = 'alpaca_api_secret_key';
  static const _keySecUserAgent = 'sec_user_agent';
  static const _keyRiskPct = 'risk_pct_override'; // optional override of the 2% default
  static const _keyAutoTradeEnabled = 'auto_trade_enabled';
  static const _keyDaemonManualOverride = 'daemon_manual_override'; // null | 'force_on' | 'force_off'

  Future<String?> getAlpacaApiKeyId() => _storage.read(key: _keyApiKeyId);
  Future<void> setAlpacaApiKeyId(String value) => _storage.write(key: _keyApiKeyId, value: value);

  Future<String?> getAlpacaApiSecret() => _storage.read(key: _keyApiSecret);
  Future<void> setAlpacaApiSecret(String value) => _storage.write(key: _keyApiSecret, value: value);

  /// SEC fair-access policy requires a real, identifying User-Agent on every
  /// request (https://www.sec.gov/os/accessing-edgar-data). Spec default is
  /// "PennyFlipQuantEngine jrblackrose@research.local"; users should replace
  /// the email with their own contact before scanning at volume.
  Future<String> getSecUserAgent() async {
    return await _storage.read(key: _keySecUserAgent) ??
        'PennyFlipQuantEngine jrblackrose@research.local';
  }

  Future<void> setSecUserAgent(String value) => _storage.write(key: _keySecUserAgent, value: value);

  Future<double> getRiskPct() async {
    final raw = await _storage.read(key: _keyRiskPct);
    return raw != null ? double.tryParse(raw) ?? 0.02 : 0.02;
  }

  Future<void> setRiskPct(double value) => _storage.write(key: _keyRiskPct, value: value.toString());

  Future<bool> getAutoTradeEnabled() async {
    return (await _storage.read(key: _keyAutoTradeEnabled)) == 'true';
  }

  Future<void> setAutoTradeEnabled(bool value) =>
      _storage.write(key: _keyAutoTradeEnabled, value: value.toString());

  /// Manual override for the daemon status banner: null = follow the market
  /// clock automatically (default), 'force_on' = run regardless of clock
  /// (useful for testing), 'force_off' = never run (kill switch).
  Future<String?> getDaemonManualOverride() => _storage.read(key: _keyDaemonManualOverride);

  Future<void> setDaemonManualOverride(String? value) async {
    if (value == null) {
      await _storage.delete(key: _keyDaemonManualOverride);
    } else {
      await _storage.write(key: _keyDaemonManualOverride, value: value);
    }
  }

  Future<bool> hasCredentials() async {
    final k = await getAlpacaApiKeyId();
    final s = await getAlpacaApiSecret();
    return (k != null && k.isNotEmpty) && (s != null && s.isNotEmpty);
  }

  Future<void> clearAll() => _storage.deleteAll();
}
