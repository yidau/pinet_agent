import 'dart:async';
import 'dart:io';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'enrollment/enrollment_profile.dart';
import 'enrollment/enrollment_screen.dart';
import 'telemetry/dashboard_page.dart';
import 'telemetry/message_page.dart';
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
    if (mounted) setState(() {});
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
        builder: (_) => EnrollmentScreen(
          profile: _profile,
          onRegistered: _registered,
        ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = [
      DashboardPage(
        connection: _telemetry,
        onOpenMessages: () => setState(() => _tab = 1),
      ),
      MessagePage(connection: _telemetry),
      const _AiDeferredPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Symbols.radar, color: theme.colorScheme.primary),
            const SizedBox(width: 9),
            const Text('PocketNet'),
          ],
        ),
        actions: [
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
            if (_profile != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.devices, size: 17,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(child: Text('设备 · ${_profile!.piId}')),
                    Text(
                      switch (_telemetry.phase) {
                        TelemetryPhase.live => '实时连接',
                        TelemetryPhase.connecting => '连接中',
                        TelemetryPhase.retrying => '重连中',
                        TelemetryPhase.denied => '未授权',
                        TelemetryPhase.incompatible => '版本不兼容',
                        TelemetryPhase.stopped => '未连接',
                      },
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: IndexedStack(index: _tab, children: tabs),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '仪表盘',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _telemetry.unreadCount > 0,
              label: Text('${_telemetry.unreadCount}'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications),
            label: '消息',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: 'AI（暂缓）',
          ),
        ],
      ),
    );
  }
}

class _AiDeferredPage extends StatelessWidget {
  const _AiDeferredPage();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 42,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('AI 功能暂缓开发',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            '当前版本专注于持续监测、实时仪表盘和安全事件管理。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
