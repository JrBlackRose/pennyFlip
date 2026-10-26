import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../../models/daemon_status.dart';
import '../../models/pipeline_result.dart';
import '../../services/background_service.dart';
import '../../services/market_clock_service.dart';
import '../../services/scan_orchestrator.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../widgets/candidate_card.dart';
import '../widgets/market_clock_banner.dart';
import '../widgets/pipeline_funnel.dart';
import 'self_test_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DaemonStatus _daemonStatus = DaemonStatus.initial;
  final List<CandidateResult> _candidates = [];
  StreamSubscription<CandidateResult>? _candidateSub;
  StreamSubscription<Map<String, dynamic>?>? _statusSub;
  bool _manualScanInFlight = false;

  int get _scanned => _candidates.length;
  int get _module1Pass => _candidates.where((c) => c.module1?.passed == true).length;
  int get _module2Pass => _candidates.where((c) => c.module2?.passed == true).length;
  int get _module3Pass => _candidates.where((c) => c.module3?.passed == true).length;
  int get _module3Veto => _candidates.where((c) => c.module3?.vetoed == true).length;
  int get _module4Approved => _candidates.where((c) => c.stage == PipelineStage.approved).length;

  @override
  void initState() {
    super.initState();
    _refreshClockSnapshot();
    _subscribeToService();
    _candidateSub = ScanOrchestrator.instance.updates.listen((result) {
      if (!mounted) return;
      setState(() {
        final idx = _candidates.indexWhere((c) => c.cik10 == result.cik10);
        if (idx >= 0) {
          _candidates[idx] = result;
        } else {
          _candidates.insert(0, result);
        }
        if (_candidates.length > 100) _candidates.removeLast();
      });
    });
  }

  void _subscribeToService() {
    final service = FlutterBackgroundService();
    _statusSub = service.on(BackgroundServiceController.statusChannelEvent).listen((event) {
      if (!mounted || event == null) return;
      setState(() {
        _daemonStatus = _daemonStatus.copyWith(
          isActive: event['is_active'] as bool? ?? _daemonStatus.isActive,
          nextOpenUtc:
              event['next_open_utc'] != null ? DateTime.parse(event['next_open_utc'] as String) : null,
          nextCloseUtc:
              event['next_close_utc'] != null ? DateTime.parse(event['next_close_utc'] as String) : null,
          lastTickUtc:
              event['last_tick_utc'] != null ? DateTime.parse(event['last_tick_utc'] as String) : null,
          clockSource: event['clock_source'] as String?,
        );
      });
    });
  }

  Future<void> _refreshClockSnapshot() async {
    final snapshot = await MarketClockService.instance.getSnapshot();
    final override = await SettingsService.instance.getDaemonManualOverride();
    if (!mounted) return;
    setState(() {
      _daemonStatus = _daemonStatus.copyWith(
        isActive: _daemonStatus.isActive, // real activity state comes from the service broadcast
        nextOpenUtc: snapshot.nextOpenUtc,
        nextCloseUtc: snapshot.nextCloseUtc,
        clockSource: snapshot.source.name,
        manualOverride: override,
        clearManualOverride: override == null,
      );
    });
  }

  @override
  void dispose() {
    _candidateSub?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  Future<void> _onStartNow() async {
    await SettingsService.instance.setDaemonManualOverride(null);
    await BackgroundServiceController.manualStart();
    await _refreshClockSnapshot();
  }

  Future<void> _onStopNow() async {
    await BackgroundServiceController.manualStop();
    setState(() => _daemonStatus = _daemonStatus.copyWith(isActive: false));
  }

  Future<void> _onForceOverrideChanged(bool enableForceOn) async {
    if (!enableForceOn) {
      await SettingsService.instance.setDaemonManualOverride(null);
      await _refreshClockSnapshot();
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => _OverrideSheet(),
    );
    if (choice == null) return;
    await SettingsService.instance.setDaemonManualOverride(choice == 'clear' ? null : choice);
    if (choice == 'force_on') {
      await BackgroundServiceController.manualStart();
    } else if (choice == 'force_off') {
      await BackgroundServiceController.manualStop();
    }
    await _refreshClockSnapshot();
  }

  Future<void> _runManualScanCycle() async {
    if (_manualScanInFlight) return;
    setState(() => _manualScanInFlight = true);
    try {
      await ScanOrchestrator.instance.runCycle(trigger: 'manual_dashboard');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan cycle error: $e')));
      }
    } finally {
      if (mounted) setState(() => _manualScanInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('pennyFlip'),
            const SizedBox(width: 8),
            Text('SNIPER', style: AppTheme.mono(size: 11, color: AppColors.accentPrimary, weight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Run Self-Test',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SelfTestScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshClockSnapshot,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            MarketClockBanner(
              status: _daemonStatus,
              onStartNow: _onStartNow,
              onStopNow: _onStopNow,
              onForceOverrideChanged: _onForceOverrideChanged,
            ),
            const SizedBox(height: 14),
            PipelineFunnel(
              scanned: _scanned,
              module1Pass: _module1Pass,
              module2Pass: _module2Pass,
              module3Pass: _module3Pass,
              module3Veto: _module3Veto,
              module4Approved: _module4Approved,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('CANDIDATE FEED',
                    style: AppTheme.mono(size: 12, weight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 0.8)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _manualScanInFlight ? null : _runManualScanCycle,
                  icon: _manualScanInFlight
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(_manualScanInFlight ? 'Scanning…' : 'Scan now'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'No candidates yet.\nTap "Scan now" or wait for the daemon to wake at market open.',
                    textAlign: TextAlign.center,
                    style: AppTheme.mono(size: 12, color: AppColors.textTertiary),
                  ),
                ),
              )
            else
              for (final c in _candidates) ...[
                CandidateCard(result: c),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _OverrideSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MANUAL DAEMON OVERRIDE',
                style: AppTheme.mono(size: 13, weight: FontWeight.w800, letterSpacing: 0.6)),
            const SizedBox(height: 6),
            Text(
              'Overrides the automatic US market-hours clock. Remember to clear this when done.',
              style: AppTheme.mono(size: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_circle_outline, color: AppColors.signalPass),
              title: const Text('Force ON — run regardless of clock'),
              onTap: () => Navigator.of(context).pop('force_on'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.stop_circle_outlined, color: AppColors.signalFail),
              title: const Text('Force OFF — kill switch'),
              onTap: () => Navigator.of(context).pop('force_off'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_open, color: AppColors.textSecondary),
              title: const Text('Clear override — follow the market clock'),
              onTap: () => Navigator.of(context).pop('clear'),
            ),
          ],
        ),
      ),
    );
  }
}
