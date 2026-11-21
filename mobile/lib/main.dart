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
import 'time_sync/time_sync_screen.dart';
import 'ui/dashboard_pages.dart';

void main() => runApp(const PiAgentApp());

class PiAgentApp extends StatelessWidget {
  const PiAgentApp({super.key, this.history, this.initialConnection});

  final History? history;
  final Connection? initialConnection;

  @override
  Widget build(BuildContext context) {
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff57def3),
          brightness: Brightness.dark,
        ).copyWith(
          primary: const Color(0xff57def3),
          onPrimary: const Color(0xff062831),
          surface: const Color(0xff0b1422),
          surfaceContainer: const Color(0xff152234),
          surfaceContainerLow: const Color(0xff111d2d),
          surfaceContainerHigh: const Color(0xff1b2a3e),
          onSurface: const Color(0xffedf5ff),
          onSurfaceVariant: const Color(0xff9cafc5),
          outlineVariant: const Color(0xff2b3e56),
        );
    return MaterialApp(
      title: 'PocketNet AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: colors.surface,
        cardTheme: CardThemeData(
          color: colors.surfaceContainerLow,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.outlineVariant),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: colors.surfaceContainerLow,
          indicatorColor: colors.primary.withValues(alpha: 0.17),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? colors.primary
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          filled: true,
        ),
      ),
      home: ChatScreen(history: history, initialConnection: initialConnection),
    );
  }
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
  const ChatScreen({super.key, this.history, this.initialConnection});

  final History? history;
  final Connection? initialConnection;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _draft = TextEditingController();
  final _device = DeviceConnection();
  late final _history = widget.history ?? History();
  final _entries = <ChatEntry>[];
  final _observations = <String, Json>{};
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
    unawaited(_restore());
  }

  @override
  void dispose() {
    _device.removeListener(_onDeviceChanged);
    _device.dispose();
    _client?.close();
    _draft.dispose();
    super.dispose();
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
      }
      if (changedCapabilities) {
        _observationRegistry = session?.registry;
        _observations.clear();
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
    setState(() => _selectedTab = index);
    if (_device.session case final session?) {
      if ((index == 1 || index == 2) && session.registry.kismet != null) {
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
    final names = switch (_selectedTab) {
      0 => [
        'get_system_info',
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
      2 => ['list_captures', 'get_capture_status'],
      _ => <String>[],
    };
    for (final name in names) {
      final tool = session.registry[name];
      if (tool == null || !tool.isCallable) continue;
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
    });
  }

  Future<void> _connect() async {
    final connection = _connection;
    if (connection == null) {
      await _settings();
      return;
    }
    await _device.connect(
      endpoint: connection.mcp,
      token: connection.token,
      createHttpClient: connection.deviceClient,
    );
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
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'PocketNet AI',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
        actions: [
          if (Platform.isAndroid || Platform.isIOS)
            IconButton(
              tooltip: '手机注册',
              icon: const Icon(Symbols.qr_code_scanner),
              onPressed: _busy || _loading ? null : _enrollmentSettings,
            ),
          if (Platform.isAndroid || Platform.isIOS)
            IconButton(
              tooltip: '蓝牙校时',
              icon: const Icon(Symbols.schedule),
              onPressed: _busy || _loading
                  ? null
                  : () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => TimeSyncScreen(profile: _enrollment),
                      ),
                    ),
            ),
          IconButton(
            onPressed: _busy || _loading ? null : _settings,
            icon: const Icon(Symbols.settings),
            tooltip: _connection == null ? '配置连接' : '连接设置',
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _selectTab,
        height: 68,
        destinations: const [
          NavigationDestination(
            icon: Icon(Symbols.dashboard),
            selectedIcon: Icon(Symbols.dashboard, fill: 1),
            label: 'Overview',
          ),
          NavigationDestination(icon: Icon(Symbols.wifi), label: 'Wireless'),
          NavigationDestination(
            icon: Icon(Symbols.folder),
            selectedIcon: Icon(Symbols.folder, fill: 1),
            label: 'Captures',
          ),
          NavigationDestination(
            icon: Icon(Symbols.chat_bubble),
            selectedIcon: Icon(Symbols.chat_bubble, fill: 1),
            label: 'AI',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DevicePanel(
                    connection: _device,
                    endpoint: _connection?.mcp,
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
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text('无法读取手机的注册信息。可以重新扫码注册。'),
                  ),
                Expanded(
                  child: switch (_selectedTab) {
                    0 => OverviewPage(
                      session: session,
                      observations: _observations,
                      onOpenAi: () => _selectTab(3),
                    ),
                    1 => WirelessPage(
                      session: session,
                      observations: _observations,
                    ),
                    2 => CapturesPage(
                      session: session,
                      observations: _observations,
                    ),
                    _ => _analysis(context),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _analysis(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('AI 调查', style: theme.textTheme.titleLarge),
          if (_historyWarning)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('本地历史记录暂不可用。'),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                ? _welcome(context)
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) =>
                        _entry(context, _entries[_entries.length - 1 - index]),
                  ),
          ),
          if (_busy) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _activeTool == null ? '正在分析…' : '正在调用 $_activeTool',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const LinearProgressIndicator(minHeight: 2),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    maxLines: 5,
                    minLines: 1,
                    maxLength: 12000,
                    decoration: const InputDecoration(
                      hintText: '询问设备或网络状态…',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _busy || _loading ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  tooltip: '发送消息',
                  style: IconButton.styleFrom(minimumSize: const Size(48, 52)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text('询问当前设备的观测数据', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, prompt) in [
                  ('查看系统状态', '查看树莓派的系统信息、CPU、内存、磁盘和温度。'),
                  ('查看网络状态', '查看树莓派当前可用的网络信息。'),
                ])
                  ActionChip(
                    label: Text(label),
                    onPressed: () => _draft.text = prompt,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, ChatEntry entry) {
    final colors = Theme.of(context).colorScheme;
    if (entry.role == 'tool' || entry.role == 'error') {
      final color = entry.role == 'error'
          ? colors.error
          : colors.onSurfaceVariant;
      if (entry.details?.isNotEmpty == true) {
        return ExpansionTile(
          leading: Icon(Icons.terminal, size: 18, color: color),
          title: Text(entry.text, style: TextStyle(color: color)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SelectableText(
                entry.details!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        child: Text(entry.text, style: TextStyle(color: color)),
      );
    }
    final user = entry.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 570),
        margin: EdgeInsets.only(
          left: user ? 36 : 0,
          right: user ? 0 : 36,
          top: 6,
          bottom: 6,
        ),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: user ? colors.primaryContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          entry.text,
          style: TextStyle(
            color: user ? colors.onPrimaryContainer : colors.onSurface,
          ),
        ),
      ),
    );
  }
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
