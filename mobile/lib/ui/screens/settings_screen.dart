import 'package:flutter/material.dart';

import '../../db/app_database.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();
  final _userAgentController = TextEditingController();
  final _riskPctController = TextEditingController();

  bool _obscureKey = true;
  bool _obscureSecret = true;
  bool _autoTradeEnabled = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = SettingsService.instance;
    final key = await s.getAlpacaApiKeyId();
    final secret = await s.getAlpacaApiSecret();
    final ua = await s.getSecUserAgent();
    final risk = await s.getRiskPct();
    final auto = await s.getAutoTradeEnabled();
    if (!mounted) return;
    setState(() {
      _apiKeyController.text = key ?? '';
      _apiSecretController.text = secret ?? '';
      _userAgentController.text = ua;
      _riskPctController.text = (risk * 100).toStringAsFixed(1);
      _autoTradeEnabled = auto;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final s = SettingsService.instance;
    await s.setAlpacaApiKeyId(_apiKeyController.text.trim());
    await s.setAlpacaApiSecret(_apiSecretController.text.trim());
    await s.setSecUserAgent(
        _userAgentController.text.trim().isEmpty ? await s.getSecUserAgent() : _userAgentController.text.trim());
    final riskPct = double.tryParse(_riskPctController.text.trim());
    if (riskPct != null && riskPct > 0 && riskPct <= 100) {
      await s.setRiskPct(riskPct / 100);
    }
    await s.setAutoTradeEnabled(_autoTradeEnabled);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved to secure on-device storage')),
    );
  }

  Future<void> _confirmWipeLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgSurface,
        title: const Text('Clear local data?'),
        content: const Text(
          'Deletes all cached SEC entities, filings, OHLCV bars and scan/order logs from this '
          'device. Your Alpaca and SEC credentials are not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear', style: TextStyle(color: AppColors.signalFail)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppDatabase.instance.wipeAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local data cleared')));
      }
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _apiSecretController.dispose();
    _userAgentController.dispose();
    _riskPctController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionLabel('ALPACA PAPER TRADING'),
                const SizedBox(height: 8),
                _card([
                  _field(
                    controller: _apiKeyController,
                    label: 'APCA-API-KEY-ID',
                    obscure: _obscureKey,
                    onToggleObscure: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _apiSecretController,
                    label: 'APCA-API-SECRET-KEY',
                    obscure: _obscureSecret,
                    onToggleObscure: () => setState(() => _obscureSecret = !_obscureSecret),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Paper trading only — this app never references a live-money Alpaca '
                    'endpoint. Keys are stored in Android Keystore via flutter_secure_storage, '
                    'never in the SQLite database or on any server.',
                    style: AppTheme.mono(size: 10.5, color: AppColors.textTertiary),
                  ),
                ]),
                const SizedBox(height: 20),
                _sectionLabel('SEC EDGAR'),
                const SizedBox(height: 8),
                _card([
                  _field(
                    controller: _userAgentController,
                    label: 'User-Agent (SEC fair-access policy requires a contact email)',
                    obscure: false,
                  ),
                ]),
                const SizedBox(height: 20),
                _sectionLabel('RISK'),
                const SizedBox(height: 8),
                _card([
                  _field(
                    controller: _riskPctController,
                    label: 'Risk per trade (% of settled cash)',
                    obscure: false,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _autoTradeEnabled,
                    onChanged: (v) => setState(() => _autoTradeEnabled = v),
                    title: const Text('Auto-route approved orders'),
                    subtitle: Text(
                      'When off, Module 4 sizes positions but does not submit orders — review and '
                      'trade manually.',
                      style: AppTheme.mono(size: 10.5, color: AppColors.textTertiary),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                _sectionLabel('DATA'),
                const SizedBox(height: 8),
                _card([
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline, color: AppColors.signalFail),
                    title: const Text('Clear local scan data'),
                    subtitle: Text('Entities, filings, bars, order log',
                        style: AppTheme.mono(size: 10.5, color: AppColors.textTertiary)),
                    onTap: _confirmWipeLocalData,
                  ),
                ]),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Save settings'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) =>
      Text(text, style: AppTheme.mono(size: 11, weight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 0.8));

  Widget _card(List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: AppTheme.mono(size: 13),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: onToggleObscure,
              )
            : null,
      ),
    );
  }
}
