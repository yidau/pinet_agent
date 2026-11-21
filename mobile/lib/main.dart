import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'agent/agent.dart';
import 'llm/deepseek.dart';
import 'llm/llm_client.dart';
import 'mcp/mcp_client.dart';
import 'network.dart';
import 'storage/history.dart';

void main() => runApp(const PiAgentApp());

class PiAgentApp extends StatelessWidget {
  const PiAgentApp({super.key, this.history});

  final History? history;

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xff73d8b1),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'PiAgent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xff0c1617),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
        ),
      ),
      home: ChatScreen(history: history),
    );
  }
}

class Connection {
  const Connection(this.mcp, this.token, this.llm, this.apiKey, this.model);

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
  const ChatScreen({super.key, this.history});

  final History? history;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _draft = TextEditingController();
  late final _history = widget.history ?? History();
  final _entries = <ChatEntry>[];
  Connection? _connection;
  http.Client? _client;
  http.Client? _mcpClient;
  String? _activeTool;
  bool _busy = false;
  bool _loading = true;
  bool _historyWarning = false;

  @override
  void initState() {
    super.initState();
    _connection = Connection.fromBuildConfiguration();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _client?.close();
    _mcpClient?.close();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final entries = await _history.load();
      if (mounted) setState(() => _entries.addAll(entries));
    } catch (_) {
      if (mounted) setState(() => _historyWarning = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
      setState(() => _connection = connection);
    }
  }

  Future<void> _send() async {
    final message = _draft.text.trim();
    if (_busy || _loading || message.isEmpty) return;
    final connection = _connection;
    if (connection == null) {
      await _settings();
      return;
    }
    final conversation = _entries
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
    _draft.clear();
    final client = http.Client();
    _client = client;
    try {
      final deviceClient = mcpHttpClient(connection.mcp);
      _mcpClient = deviceClient;
      await _record(ChatEntry('user', message));
      final apiKey = await connection.resolveApiKey();
      final reply =
          await Agent(
            McpClient(deviceClient, connection.mcp, connection.token),
            LlmClient(client, connection.llm, apiKey, connection.model),
          ).run(
            message,
            history: previous,
            onEvent: (event) {
              if (mounted) {
                setState(
                  () => _activeTool = event.running ? event.label : null,
                );
              }
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
      await _record(ChatEntry('assistant', reply));
    } on FormatException catch (error) {
      await _record(ChatEntry('error', error.message));
    } catch (_) {
      await _record(const ChatEntry('error', '连接中断。请检查网络、证书和连接设置。'));
    } finally {
      client.close();
      _client = null;
      _mcpClient?.close();
      _mcpClient = null;
      if (mounted) {
        setState(() {
          _activeTool = null;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PiAgent'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _settings,
            icon: const Icon(Icons.settings_ethernet),
            label: Text(_connection == null ? '配置连接' : '连接设置'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
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
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            itemCount: _entries.length,
                            itemBuilder: (context, index) => _entry(
                              context,
                              _entries[_entries.length - 1 - index],
                            ),
                          ),
                  ),
                  if (_activeTool != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('正在调用 $_activeTool'),
                    ),
                  if (_busy) const LinearProgressIndicator(),
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
                              hintText: '给树莓派下达任务…',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: _busy || _loading ? null : _send,
                          icon: const Icon(Icons.arrow_upward),
                          tooltip: '发送任务',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(52, 54),
                            backgroundColor: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
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
            Icon(
              Icons.terminal_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('树莓派开发台', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, prompt) in [
                  ('查看系统状态', '查看树莓派的系统信息、CPU、内存、磁盘和温度。'),
                  ('浏览工作区', '列出 workspace 根目录中的文件和项目。'),
                  ('运行 C++17 验收', acceptancePrompt),
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
  http.Client? _probeClient;
  bool _saving = false;
  String? _systemInfo;
  String? _error;

  @override
  void dispose() {
    _probeClient?.close();
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
    if (token.length < 32) {
      throw const FormatException('请输入至少 32 个字符的设备令牌。');
    }
    return (mcp, token);
  }

  Future<void> _testConnection() async {
    http.Client? client;
    try {
      final (endpoint, token) = _deviceSettings();
      client = mcpHttpClient(endpoint);
      setState(() {
        _probeClient = client;
        _systemInfo = null;
        _error = null;
      });
      final mcp = McpClient(client, endpoint, token);
      await mcp.initialize();
      final info = await mcp.callTool('get_system_info', {});
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
      client?.close();
      if (mounted && client != null) setState(() => _probeClient = null);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final (mcp, token) = _deviceSettings();
      final llm = serviceUri(_llm.text);
      final apiKey = _apiKey.text.trim();
      final model = _model.text.trim();
      if (model.isEmpty) {
        throw const FormatException('请填写聊天使用的模型名称。');
      }
      final connection = Connection(mcp, token, llm, apiKey, model);
      await connection.resolveApiKey();
      if (mounted) Navigator.pop(context, connection);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final probing = _probeClient != null;
    final working = probing || _saving;
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
                onPressed: working ? null : _testConnection,
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
              const Text('连接设置保存在当前应用进程中。'),
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
          onPressed: working ? null : _save,
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
      enabled: _probeClient == null && !_saving,
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
