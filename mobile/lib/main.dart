import 'dart:async';
import 'dart:io';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'enrollment/enrollment_profile.dart';
import 'enrollment/enrollment_screen.dart';
import 'telemetry/dashboard_page.dart';
import 'telemetry/message_page.dart';
import 'telemetry/monitoring_widgets.dart';
import 'telemetry/normal_monitor_page.dart';
import 'telemetry/telemetry_connection.dart';
import 'time_sync/time_sync_screen.dart';
import 'ui/console_style.dart';

void main() => runApp(const PocketNetApp());

class PocketNetApp extends StatefulWidget {
  const PocketNetApp({super.key});

  @override
  State<PocketNetApp> createState() => _PocketNetAppState();
}

class _PocketNetAppState extends State<PocketNetApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PocketNet',
    debugShowCheckedModeBanner: false,
    theme: consoleTheme(Brightness.light),
    darkTheme: consoleTheme(Brightness.dark),
    themeMode: _themeMode,
    home: PocketNetHome(
      onToggleTheme: () => setState(() {
        _themeMode = _themeMode == ThemeMode.dark
            ? ThemeMode.light
            : ThemeMode.dark;
      }),
    ),
  );
}

class PocketNetHome extends StatefulWidget {
  const PocketNetHome({super.key, required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<PocketNetHome> createState() => _PocketNetHomeState();
}

class _PocketNetHomeState extends State<PocketNetHome>
    with WidgetsBindingObserver {
  final _telemetry = TelemetryConnection();
  EnrollmentProfile? _profile;
  int _tab = 0;
  bool _loading = true;
  bool _profileError = false;
  TelemetryPhase _shownPhase = TelemetryPhase.stopped;
  bool _shownRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _telemetry.addListener(_changed);
    unawaited(_restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telemetry.removeListener(_changed);
    _telemetry.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted ||
        (_shownPhase == _telemetry.phase &&
            _shownRequested == _telemetry.isRequested)) {
      return;
    }
    setState(() {
      _shownPhase = _telemetry.phase;
      _shownRequested = _telemetry.isRequested;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _telemetry.setForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _telemetry.setForeground(false);
    }
  }

  Future<void> _restore() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        _profile = await EnrollmentProfile.load();
        if (_profile case final profile?) {
          _telemetry.useTarget(TelemetryTarget.fromEnrollment(profile));
        }
      } catch (_) {
        _profileError = true;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _registered(EnrollmentProfile profile) {
    setState(() {
      _profile = profile;
      _profileError = false;
    });
    _telemetry.useTarget(TelemetryTarget.fromEnrollment(profile));
  }

  Future<void> _openEnrollment() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            EnrollmentScreen(profile: _profile, onRegistered: _registered),
      ),
    );
  }

  Future<void> _openTimeSync() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TimeSyncScreen(profile: _profile)),
    );
  }

  void _disconnectTelemetry() {
    _telemetry.stop();
  }

  void _openMessages() {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('消息中心')),
            body: SafeArea(child: MessagePage(connection: _telemetry)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (connectionLabel, connectionStatus) = switch (_telemetry.phase) {
      TelemetryPhase.live when !_telemetry.stale => (
        '已连接',
        MonitorStatus.normal,
      ),
      TelemetryPhase.live => ('数据过期', MonitorStatus.limited),
      TelemetryPhase.connecting => ('连接中', MonitorStatus.limited),
      TelemetryPhase.retrying => ('重连中', MonitorStatus.limited),
      TelemetryPhase.denied => ('未授权', MonitorStatus.failed),
      TelemetryPhase.incompatible => ('版本不兼容', MonitorStatus.failed),
      TelemetryPhase.stopped => ('未连接', MonitorStatus.unknown),
    };
    final tabs = [
      DashboardPage(connection: _telemetry, onOpenMessages: _openMessages),
      NormalMonitorPage(connection: _telemetry, active: _tab == 1),
      const _UnavailablePage(title: '深度检测'),
      const _UnavailablePage(title: '主动测试'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Symbols.radar, color: theme.colorScheme.primary),
            const SizedBox(width: 9),
            const Flexible(
              child: Text('PocketNet', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          if (_profile case final profile?)
            TextButton(
              onPressed: () => showMonitoringSheet(
                context,
                (_) => MonitoringSheetBody(
                  '设备连接',
                  children: [
                    ListTile(
                      title: const Text('设备'),
                      subtitle: Text(profile.piId),
                    ),
                    ListTile(
                      leading: connectionStatus.indicator(context),
                      title: Text(connectionLabel),
                    ),
                  ],
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: connectionStatus.color(context),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  connectionStatus.indicator(context, size: 13),
                  const SizedBox(width: 4),
                  Text(
                    connectionLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: connectionStatus.color(context),
                    ),
                  ),
                ],
              ),
            ),
          PopupMenuButton<String>(
            tooltip: '设备设置',
            onSelected: (value) {
              switch (value) {
                case 'register':
                  unawaited(_openEnrollment());
                  break;
                case 'clock':
                  unawaited(_openTimeSync());
                  break;
                case 'disconnect':
                  _disconnectTelemetry();
                  break;
                case 'reconnect':
                  _telemetry.reconnect();
                  break;
                case 'theme':
                  widget.onToggleTheme();
                  break;
              }
            },
            itemBuilder: (_) => [
              if (Platform.isAndroid || Platform.isIOS) ...[
                const PopupMenuItem(
                  value: 'register',
                  child: ListTile(
                    leading: Icon(Icons.qr_code_scanner),
                    title: Text('手机注册'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'clock',
                  child: ListTile(
                    leading: Icon(Icons.schedule),
                    title: Text('蓝牙校时'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              if (_telemetry.isRequested)
                const PopupMenuItem(
                  value: 'disconnect',
                  child: ListTile(
                    leading: Icon(Icons.link_off),
                    title: Text('断开遥测'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (_profile != null)
                const PopupMenuItem(
                  value: 'reconnect',
                  child: ListTile(
                    leading: Icon(Icons.refresh),
                    title: Text('重新连接设备'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  leading: Icon(Icons.brightness_6_outlined),
                  title: Text('切换外观'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_profileError)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text('无法读取手机注册信息，可以重新扫码注册。'),
              ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  for (final (index, page) in tabs.indexed)
                    TickerMode(enabled: _tab == index, child: page),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '仪表盘',
          ),
          const NavigationDestination(icon: Icon(Icons.radar), label: '常态监控'),
          const NavigationDestination(
            icon: Icon(Icons.travel_explore),
            label: '深度检测',
          ),
          const NavigationDestination(
            icon: Icon(Icons.lock_outline),
            label: '主动测试',
          ),
        ],
      ),
    );
  }
}

class _UnavailablePage extends StatelessWidget {
  const _UnavailablePage({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 42,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('尚未开放', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
