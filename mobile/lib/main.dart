import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'agent/agent.dart';
import 'enrollment/enrollment_profile.dart';
import 'enrollment/enrollment_screen.dart';
import 'llm/deepseek.dart';
import 'llm/llm_client.dart';
import 'mcp/device_connection.dart';
import 'mcp/device_panel.dart';
import 'mcp/mcp_client.dart';
import 'mcp/tool_registry.dart';
import 'network.dart';
import 'storage/history.dart';
import 'telemetry/dashboard_page.dart';
import 'telemetry/message_page.dart';
import 'telemetry/telemetry_connection.dart';
import 'time_sync/time_sync_screen.dart';
import 'ui/capture_workspace.dart';
import 'ui/console_style.dart';
import 'ui/investigation_workspace.dart';
import 'ui/overview_workspace.dart';
import 'ui/wireless_workspace.dart';

void main() => runApp(const PiAgentApp());

class PiAgentApp extends StatefulWidget {
  const PiAgentApp({super.key, this.history, this.initialConnection});
  final History? history;
  final Connection? initialConnection;
  @override
  State<PiAgentApp> createState() => _PiAgentAppState();
}

class _PiAgentAppState extends State<PiAgentApp> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PocketNet AI',
    debugShowCheckedModeBanner: false,
    theme: consoleTheme(Brightness.light),
    darkTheme: consoleTheme(Brightness.dark),
    themeMode: _mode,
    home: ChatScreen(
      history: widget.history,
      initialConnection: widget.initialConnection,
      toggleTheme: () => setState(
        () =>
            _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      ),
    ),
  );
}

class Connection {
  const Connection(
    this.mcp,
    this.token,
    this.llm,
    this.apiKey,
    this.model, {
    this.enrollmentCa,
  });

  factory Connection.fromEnrollment(
    EnrollmentProfile profile,
    Connection? previous,
  ) => Connection(
    profile.mcpUrl,
    profile.token,
    previous?.llm ?? Uri.parse(deepSeekChatUrl),
    previous?.apiKey ?? '',
    previous?.model ?? deepSeekDefaultModel,
    enrollmentCa: profile.caPem,
  );

  static Connection? fromBuildConfiguration() {
    const token = String.fromEnvironment('PIAGENT_MCP_TOKEN');
    if (bundledMcpUrl.isEmpty || token.isEmpty) return null;
    return Connection(
      serviceUri(bundledMcpUrl),
      token,
      Uri.parse(deepSeekChatUrl),
      '',
      deepSeekDefaultModel,
    );
  }

  final Uri mcp;
  final String token;
  final Uri llm;
  final String apiKey;
  final String model;
  final String? enrollmentCa;

  http.Client deviceClient() => mcpHttpClient(mcp, caPem: enrollmentCa);

  Future<String> resolveApiKey() async {
    if (apiKey.isNotEmpty) return apiKey;
    if (isDeepSeekEndpoint(llm)) {
      const buildKey = String.fromEnvironment('PIAGENT_DEEPSEEK_KEY');
      if (buildKey.isNotEmpty) return buildKey;
      final localKey = await readDeepSeekApiKey();
      if (localKey != null) return localKey;
    }
    throw const FormatException('请填写云端 API Key，或配置本地 DeepSeek 密钥文件。');
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.history,
    this.initialConnection,
    this.toggleTheme,
  });
  final VoidCallback? toggleTheme;

  final History? history;
  final Connection? initialConnection;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _freshFor = Duration(seconds: 30);
  final _elapsed = Stopwatch()..start();
  late final _tabMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );
  Animation<Offset> _tabOffset = const AlwaysStoppedAnimation(Offset.zero);
  final _workspaces = List<Widget?>.filled(5, null);
  final _draft = TextEditingController();
  final _device = DeviceConnection();
  final _telemetry = TelemetryConnection();
  late final _history = widget.history ?? History();
  final _entries = <ChatEntry>[];
  final _observations = <String, Json>{};
  final _readAt = <String, Duration>{};
  Duration _registryReadAt = Duration.zero;
  final _pendingObservations = <String>{};
  DeviceSession? _observationSession;
  ToolRegistry? _observationRegistry;
  int _selectedTab = 0;
  int _conversationStart = 0;
  Connection? _connection;
  EnrollmentProfile? _enrollment;
  http.Client? _client;
  String? _activeTool;
  bool _busy = false;
  bool _loading = true;
  bool _historyWarning = false;
  bool _enrollmentWarning = false;

  @override
  void initState() {
    super.initState();
    _connection =
        widget.initialConnection ?? Connection.fromBuildConfiguration();
    _device.addListener(_onDeviceChanged);
    _telemetry.addListener(_onTelemetryChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _telemetry.removeListener(_onTelemetryChanged);
    _telemetry.dispose();
    _tabMotion.dispose();
    _device.removeListener(_onDeviceChanged);
    _device.dispose();
    _client?.close();
    _draft.dispose();
    super.dispose();
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

  void _onTelemetryChanged() {
    if (mounted) setState(() {});
  }

  void _onDeviceChanged() {
    final session = _device.session;
    final changedSession = !identical(session, _observationSession);
    final changedCapabilities = !identical(
      session?.registry,
      _observationRegistry,
    );
    setState(() {
      if (changedSession) {
        _observationSession = session;
        _conversationStart = _entries.length;
        _observations.clear();
        _workspaces.fillRange(0, _workspaces.length, null);
      }
      if (changedCapabilities) {
        _observationRegistry = session?.registry;
        _registryReadAt = _elapsed.elapsed;
        _readAt.clear();
        _observations.removeWhere(
          (name, _) => session?.registry[name]?.isCallable != true,
        );
        _pendingObservations.clear();
      }
      if (session == null) {
        _client?.close();
        _client = null;
        _activeTool = null;
        _busy = false;
      }
    });
    if (changedCapabilities && session != null) _loadObservations(session);
  }

  void _selectTab(int index) {
    if (index == _selectedTab) return;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _tabOffset = Tween(
        begin: Offset(index > _selectedTab ? 0.025 : -0.025, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_tabMotion);
      _tabMotion.forward(from: 0);
    } else {
      _tabMotion.stop();
      _tabOffset = const AlwaysStoppedAnimation(Offset.zero);
    }
    setState(() => _selectedTab = index);
    if (_device.session case final session?) {
      if ((index == 1 || index == 2) &&
          session.registry.kismet != null &&
          _elapsed.elapsed - _registryReadAt >= _freshFor) {
        unawaited(_refreshCapabilities(session));
      } else {
        _loadObservations(session);
      }
    }
  }

  Future<void> _refreshCapabilities(DeviceSession session) async {
    try {
      await session.refreshCapabilities();
    } on FormatException {
      // DeviceConnection reports discovery failures in the device panel.
    }
  }

  void _loadObservations(DeviceSession session) {
    if (_selectedTab == 0 && _telemetry.isConfigured) return;
    final names = switch (_selectedTab) {
      0 => [
        'get_system_info',
        'get_cpu_info',
        'get_capture_status',
        'get_kismet_datasources',
        'get_network_profile',
        'get_access_points',
        'get_wireless_clients',
        if (session.registry['get_kismet_alerts'] != null)
          'get_kismet_alerts'
        else
          'get_security_events',
        'get_wireless_events',
      ],
      1 => [
        'get_access_points',
        'get_bluetooth_devices',
        'get_wireless_clients',
        'get_wifi_channels',
        'get_signal_history',
        'get_wireless_events',
      ],
      2 => [
        'list_captures',
        'get_capture_status',
        'get_kismet_datasources',
        'analyze_protocol_distribution',
        'analyze_packet_capture',
      ],
      _ => <String>[],
    };
    for (final name in names) {
      final tool = session.registry[name];
      if (tool == null || !tool.isCallable) continue;
      final readAt = _readAt[name];
      if (readAt != null && _elapsed.elapsed - readAt < _freshFor) continue;
      final requiredArguments = tool.inputSchema['required'];
      if ((requiredArguments is List && requiredArguments.isNotEmpty) ||
          !_pendingObservations.add(name)) {
        continue;
      }
      unawaited(_readObservation(session, session.registry, name));
    }
  }

  Future<void> _readObservation(
    DeviceSession session,
    ToolRegistry registry,
    String name,
  ) async {
    Json result;
    try {
      result = await session.callTool(name, {});
    } on FormatException catch (error) {
      result = {'ok': false, 'message': error.message};
    }
    if (!mounted || !identical(_observationRegistry, registry)) return;
    setState(() {
      _pendingObservations.remove(name);
      _observations[name] = result;
      _readAt[name] = _elapsed.elapsed;
    });
  }

  Future<void> _connect() async {
    final connection = _connection;
    if (connection == null) {
      await _settings();
      return;
    }
    _telemetry.start();
    await _device.connect(
      endpoint: connection.mcp,
      token: connection.token,
      createHttpClient: connection.deviceClient,
    );
  }

  void _disconnect() {
    _telemetry.stop();
    unawaited(_device.disconnect());
  }

  Future<void> _restore() async {
    await Future.wait([_restoreEnrollment(), _restoreHistory()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _restoreEnrollment() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final profile = await EnrollmentProfile.load();
      if (mounted && profile != null) _useEnrollment(profile);
    } catch (_) {
      if (mounted) setState(() => _enrollmentWarning = true);
    }
  }

  Future<void> _restoreHistory() async {
    try {
      final entries = await _history.load();
      if (mounted) setState(() => _entries.addAll(entries));
    } catch (_) {
      if (mounted) setState(() => _historyWarning = true);
    }
  }

  void _useEnrollment(EnrollmentProfile profile) => _setConnection(
    Connection.fromEnrollment(profile, _connection),
    enrollment: profile,
  );

  void _setConnection(Connection connection, {EnrollmentProfile? enrollment}) {
    final previous = _connection;
    if (previous != null &&
        (previous.mcp != connection.mcp ||
            previous.token != connection.token ||
            previous.enrollmentCa != connection.enrollmentCa)) {
      unawaited(_device.disconnect());
    }
    setState(() {
      _connection = connection;
      if (enrollment != null) {
        _enrollment = enrollment;
        _enrollmentWarning = false;
      }
    });
    final profile = _enrollment;
    final matches =
        profile != null &&
        profile.mcpUrl == connection.mcp &&
        profile.token == connection.token &&
        profile.caPem == connection.enrollmentCa;
    _telemetry.useTarget(
      matches ? TelemetryTarget.fromEnrollment(profile) : null,
    );
  }

  Future<void> _enrollmentSettings() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          EnrollmentScreen(profile: _enrollment, onRegistered: _useEnrollment),
    ),
  );

  Future<void> _record(ChatEntry entry) async {
    if (mounted) setState(() => _entries.add(entry));
    try {
      await _history.add(entry);
    } catch (_) {
      if (mounted) setState(() => _historyWarning = true);
    }
  }

  Future<void> _settings() async {
    final connection = await showDialog<Connection>(
      context: context,
      builder: (context) => _ConnectionDialog(initial: _connection),
    );
    if (mounted && connection != null) {
      _setConnection(connection);
    }
  }

  Future<void> _send() async {
    final message = _draft.text.trim();
    if (_busy || _loading || message.isEmpty) return;
    final session = _device.session;
    final connection = _connection;
    _draft.clear();
    if (session == null || connection == null) {
      await _record(ChatEntry('user', message));
      await _record(const ChatEntry('assistant', Agent.disconnectedReply));
      return;
    }
    final conversation = _entries
        .skip(_conversationStart)
        .where((entry) => entry.role == 'user' || entry.role == 'assistant')
        .where((entry) => entry.text.length <= 12000)
        .toList();
    final previous = [
      for (final entry in conversation.skip(
        conversation.length > 12 ? conversation.length - 12 : 0,
      ))
        <String, dynamic>{'role': entry.role, 'content': entry.text},
    ];
    setState(() => _busy = true);
    final client = http.Client();
    _client = client;
    bool current() =>
        mounted &&
        identical(_client, client) &&
        identical(_device.session, session);
    try {
      await _record(ChatEntry('user', message));
      if (!current()) return;
      final apiKey = await connection.resolveApiKey();
      if (!current()) return;
      final reply =
          await Agent(
            session,
            LlmClient(client, connection.llm, apiKey, connection.model),
          ).run(
            message,
            history: previous,
            onEvent: (event) {
              if (!current()) return;
              setState(() => _activeTool = event.running ? event.label : null);
              if (event.running) return;
              unawaited(
                _record(
                  ChatEntry(
                    event.failed ? 'error' : 'tool',
                    event.label,
                    details: event.output,
                  ),
                ),
              );
            },
          );
      if (current()) await _record(ChatEntry('assistant', reply));
    } on FormatException catch (error) {
      if (current()) await _record(ChatEntry('error', error.message));
    } catch (_) {
      if (current()) {
        await _record(const ChatEntry('error', '请求失败。请检查网络和连接设置。'));
      }
    } finally {
      client.close();
      if (mounted && identical(_client, client)) {
        _client = null;
        setState(() {
          _activeTool = null;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _device.session;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final enabled = !_busy && !_loading;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final telemetryMode = _telemetry.isConfigured;
    final tabs = telemetryMode ? const [0, 4, 3] : const [0, 1, 2, 3, 4];
    // Keep hidden tabs mounted without rebuilding their lists on every device reply.
    _workspaces[_selectedTab] = _workspace(_selectedTab, session);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 54,
        titleSpacing: 18,
        title: Row(
          children: [
            if (_selectedTab == 0 || _selectedTab == 3) ...[
              Icon(
                _selectedTab == 0 ? Symbols.radar : Symbols.auto_awesome,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Text(
                const [
                  'PocketNet AI',
                  '无线',
                  '采集',
                  'AI 助手',
                  '消息中心',
                ][_selectedTab],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '设备与外观设置',
            icon: const Icon(Symbols.tune),
            onSelected: (action) {
              switch (action) {
                case 'register':
                  unawaited(_enrollmentSettings());
                case 'clock':
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => TimeSyncScreen(profile: _enrollment),
                      ),
                    ),
                  );
                case 'settings':
                  unawaited(_settings());
                case 'theme':
                  widget.toggleTheme?.call();
                case 'disconnect':
                  _disconnect();
                case 'wireless':
                  _selectTab(1);
                case 'captures':
                  _selectTab(2);
              }
            },
            itemBuilder: (context) => [
              if (Platform.isAndroid || Platform.isIOS) ...[
                _menu('register', Icons.qr_code_scanner, '手机注册', enabled),
                _menu('clock', Icons.schedule, '蓝牙校时', enabled),
              ],
              _menu('settings', Icons.settings_outlined, '连接设置', enabled),
              if (telemetryMode) ...[
                _menu('wireless', Icons.wifi, '无线详情', true),
                _menu('captures', Icons.folder_open, '采集文件', true),
              ],
              _menu(
                'theme',
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                dark ? '切换浅色外观' : '切换深色外观',
                true,
              ),
              if (session != null || _telemetry.isRequested)
                _menu('disconnect', Icons.link_off, '断开连接', true),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.65,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: tabs.contains(_selectedTab)
                    ? tabs.indexOf(_selectedTab)
                    : 0,
                onDestinationSelected: (index) => _selectTab(tabs[index]),
                height:
                    64 +
                    (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(
                      0,
                      24,
                    ),
                destinations: [for (final index in tabs) _destination(index)],
              ),
            ),
      body: SafeArea(
        top: false,
        bottom: keyboardOpen,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: DevicePanel(
                    connection: _device,
                    endpoint: _connection?.mcp,
                    statusPrefix: telemetryMode ? 'MCP · ' : '',
                    configuredName:
                        _enrollment?.mcpUrl == _connection?.mcp &&
                            _enrollment?.token == _connection?.token
                        ? _enrollment?.piId
                        : null,
                    onConnect: _loading ? null : _connect,
                  ),
                ),
                if (_enrollmentWarning)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('无法读取手机的注册信息。可以重新扫码注册。'),
                  ),
                Expanded(
                  child: ClipRect(
                    child: SlideTransition(
                      position: _tabOffset,
                      textDirection: Directionality.of(context),
                      child: IndexedStack(
                        key: ObjectKey(session),
                        index: _selectedTab,
                        sizing: StackFit.expand,
                        children: [
                          for (
                            var index = 0;
                            index < _workspaces.length;
                            index++
                          )
                            TickerMode(
                              enabled: index == _selectedTab,
                              child:
                                  _workspaces[index] ?? const SizedBox.shrink(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  NavigationDestination _destination(int index) => switch (index) {
    0 => NavigationDestination(
      icon: const Icon(Symbols.space_dashboard),
      selectedIcon: const Icon(Symbols.space_dashboard, fill: 1),
      label: _telemetry.isConfigured ? '仪表盘' : '概览',
    ),
    1 => const NavigationDestination(icon: Icon(Symbols.wifi), label: '无线'),
    2 => const NavigationDestination(
      icon: Icon(Symbols.folder_open),
      selectedIcon: Icon(Symbols.folder, fill: 1),
      label: '采集',
    ),
    3 => const NavigationDestination(
      icon: Icon(Symbols.auto_awesome),
      selectedIcon: Icon(Symbols.auto_awesome, fill: 1),
      label: 'AI 助手',
    ),
    _ => NavigationDestination(
      label: '消息中心',
      icon: Badge(
        isLabelVisible: _telemetry.unreadCount > 0,
        label: Text('${_telemetry.unreadCount}'),
        child: const Icon(Icons.notifications_outlined),
      ),
    ),
  };

  Widget _workspace(int index, DeviceSession? session) => switch (index) {
    0 when _telemetry.isConfigured || _connection == null => DashboardPage(
      connection: _telemetry,
      onOpenMessages: () => _selectTab(4),
    ),
    0 => OverviewWorkspace(
      session: session,
      observations: _observations,
      aiFinding: session == null
          ? null
          : latestEvidenceFinding(_entries.skip(_conversationStart)),
      onOpenAi: () => _selectTab(3),
    ),
    1 => WirelessWorkspace(
      session: session,
      observations: _observations,
      onInvestigate: (question) {
        _draft.value = TextEditingValue(
          text: question,
          selection: TextSelection.collapsed(offset: question.length),
        );
        _selectTab(3);
      },
    ),
    2 => CaptureWorkspace(session: session, observations: _observations),
    4 => MessagePage(connection: _telemetry),
    _ => InvestigationWorkspace(
      entries: _entries,
      draft: _draft,
      activeTool: _activeTool,
      busy: _busy,
      loading: _loading,
      historyWarning: _historyWarning,
      connected: session != null,
      onSend: _send,
    ),
  };

  PopupMenuEntry<String> _menu(
    String value,
    IconData icon,
    String label,
    bool enabled,
  ) => PopupMenuItem<String>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Flexible(child: Text(label)),
      ],
    ),
  );
}

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog({this.initial});

  final Connection? initial;

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final _mcp = TextEditingController(text: widget.initial?.mcp.toString());
  late final _token = TextEditingController(text: widget.initial?.token);
  late final _llm = TextEditingController(
    text: widget.initial?.llm.toString() ?? deepSeekChatUrl,
  );
  late final _apiKey = TextEditingController(text: widget.initial?.apiKey);
  late final _model = TextEditingController(
    text: widget.initial?.model ?? deepSeekDefaultModel,
  );
  McpClient? _probeClient;
  String? _systemInfo;
  String? _error;

  @override
  void dispose() {
    unawaited(_probeClient?.close());
    for (final field in [_mcp, _token, _llm, _apiKey, _model]) {
      field.dispose();
    }
    super.dispose();
  }

  (Uri, String) _deviceSettings() {
    final mcp = serviceUri(_mcp.text);
    if (mcp.path != '/mcp') {
      throw const FormatException('树莓派地址必须以 /mcp 结尾。');
    }
    final token = _token.text.trim();
    final initial = widget.initial;
    if (initial?.enrollmentCa != null &&
        mcp != initial!.mcp &&
        token == initial.token) {
      throw const FormatException('更改树莓派地址时，请填写该地址对应的设备令牌。');
    }
    if (token.length < 32) {
      throw const FormatException('请输入至少 32 个字符的设备令牌。');
    }
    return (mcp, token);
  }

  String? _enrollmentCa(Uri endpoint) =>
      widget.initial?.mcp == endpoint ? widget.initial?.enrollmentCa : null;

  Future<void> _testConnection() async {
    McpClient? client;
    try {
      final (endpoint, token) = _deviceSettings();
      client = McpClient(
        mcpHttpClient(endpoint, caPem: _enrollmentCa(endpoint)),
        endpoint,
        token,
      );
      setState(() {
        _probeClient = client;
        _systemInfo = null;
        _error = null;
      });
      await client.initialize();
      final info = await client.callTool('get_system_info', {});
      final hostname = info['hostname'];
      final os = info['os'];
      final architecture = info['architecture'];
      final kernel = info['kernel'];
      if (hostname is! String ||
          os is! String ||
          architecture is! String ||
          kernel is! String) {
        throw const FormatException('树莓派未返回完整的系统信息。');
      }
      if (mounted) {
        setState(() {
          _systemInfo = '连接成功 · $hostname\n$os · $architecture\n内核 $kernel';
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '连接失败，请检查设备地址和网络。');
    } finally {
      await client?.close();
      if (mounted && client != null) setState(() => _probeClient = null);
    }
  }

  void _save() {
    try {
      final (mcp, token) = _deviceSettings();
      final llm = serviceUri(_llm.text);
      final apiKey = _apiKey.text.trim();
      final model = _model.text.trim();
      if (model.isEmpty) {
        throw const FormatException('请填写聊天使用的模型名称。');
      }
      final connection = Connection(
        mcp,
        token,
        llm,
        apiKey,
        model,
        enrollmentCa: _enrollmentCa(mcp),
      );
      Navigator.pop(context, connection);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final probing = _probeClient != null;
    return AlertDialog(
      title: const Text('连接树莓派和云端模型'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(
                _mcp,
                '树莓派 MCP 地址',
                hint: Platform.isWindows
                    ? 'http://127.0.0.1:19842/mcp'
                    : 'https://pi.example.net:8443/mcp',
              ),
              _input(_token, '设备令牌', secret: true),
              OutlinedButton.icon(
                onPressed: probing ? null : _testConnection,
                icon: const Icon(Icons.lan_outlined),
                label: Text(probing ? '正在查询…' : '测试树莓派连接'),
              ),
              if (_systemInfo case final info?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(info),
                ),
              const SizedBox(height: 16),
              _input(_llm, 'Chat Completions API 地址'),
              _input(_model, '模型名称'),
              _input(
                _apiKey,
                '云端 API Key',
                secret: true,
                hint: Platform.isWindows ? 'DeepSeek 可使用本地密钥文件' : null,
              ),
              Text(
                widget.initial?.enrollmentCa == null
                    ? '连接设置保存在当前应用进程中。'
                    : '注册信息保存在手机安全存储中。此处修改的设置仅在本次启动有效。',
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: probing ? null : _save,
          child: const Text('使用此连接'),
        ),
      ],
    );
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    bool secret = false,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      enabled: _probeClient == null,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) {
        if (controller == _mcp || controller == _token) {
          setState(() {
            _error = null;
            _systemInfo = null;
          });
        }
      },
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}
