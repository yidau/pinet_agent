import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../network.dart';

class McpConnectionException extends FormatException {
  const McpConnectionException(super.message);
}

class McpClient {
  McpClient(this._http, this.endpoint, this.token);

  final http.Client _http;
  final Uri endpoint;
  final String token;

  static const _preferredVersion = '2025-11-25';
  static const _supportedVersions = {_preferredVersion, '2025-06-18'};
  static const _requestTimeout = Duration(seconds: 15);
  static const _toolTimeout = Duration(seconds: 145);
  static const _closeTimeout = Duration(seconds: 3);
  static const _maxResponseBytes = 1024 * 1024;

  final _pending = <Completer<void>>{};
  String? _protocol;
  String? _sessionId;
  String? _serverName;
  Future<void>? _initialization;
  Future<void>? _closing;
  bool _initialized = false;
  bool _closed = false;
  int _nextId = 0;

  String? get serverName => _serverName;

  Future<void> initialize() async {
    _ensureOpen();
    await (_initialization ??= _initialize());
  }

  Future<void> _initialize() async {
    final reply = await _request('initialize', {
      'protocolVersion': _preferredVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'PiAgent mobile', 'version': '0.5.0'},
    });
    final version = reply['protocolVersion'];
    if (!_supportedVersions.contains(version)) {
      throw const McpConnectionException('树莓派使用了不兼容的 MCP 协议版本');
    }
    _protocol = version as String;
    final info = reply['serverInfo'];
    final name = info is Json ? info['name'] : null;
    if (name is String && name.trim().isNotEmpty) _serverName = name.trim();
    await _send('notifications/initialized', null);
    _ensureOpen();
    _initialized = true;
  }

  Future<List<Json>> listTools() async {
    _ensureInitialized();
    final tools = <Json>[];
    final seenCursors = <String>{};
    String? cursor;
    for (var page = 0; page < 5; page++) {
      final result = await _request('tools/list', {'cursor': ?cursor});
      final entries = result['tools'];
      if (entries is! List) {
        throw const McpConnectionException('树莓派返回的工具清单无效');
      }
      for (final entry in entries) {
        if (entry is! Json) {
          throw const McpConnectionException('树莓派返回的工具清单无效');
        }
        tools.add(entry);
      }
      final nextCursor = result['nextCursor'];
      if (nextCursor == null) return tools;
      if (nextCursor is! String || !seenCursors.add(nextCursor)) {
        throw const McpConnectionException('树莓派返回的工具分页信息无效');
      }
      cursor = nextCursor;
    }
    throw const McpConnectionException('树莓派返回的工具清单超过分页上限');
  }

  Future<Json> callTool(String name, Json arguments) async {
    _ensureInitialized();
    final result = await _request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    final structured = result['structuredContent'];
    final failed = result['isError'] == true;
    if (!failed && structured is Json) {
      return structured;
    }
    final content = result['content'];
    final text = content is List
        ? content
              .whereType<Json>()
              .where((item) => item['type'] == 'text')
              .map((item) => item['text'])
              .whereType<String>()
              .join('\n')
        : '';
    final message = structured is Json ? structured['message'] : null;
    return {
      if (failed && structured is Json) ...structured,
      'ok': !failed,
      'output': text.isEmpty && message is String ? message : text,
    };
  }

  Future<void> close() => _closing ??= _disconnect();

  Future<void> _disconnect() async {
    _closed = true;
    for (final request in _pending) {
      if (!request.isCompleted) request.complete();
    }
    final headers = _headers;
    final hasSession = _sessionId != null;
    _sessionId = null;
    _protocol = null;
    _serverName = null;
    _initialized = false;
    try {
      if (hasSession) {
        final request = http.Request('DELETE', endpoint)
          ..followRedirects = false
          ..headers.addAll(headers);
        await _http
            .send(request)
            .then((response) => response.stream.drain<void>())
            .timeout(_closeTimeout);
      }
    } catch (_) {
      // A server may not support DELETE, or the connection may already be lost.
    } finally {
      _http.close();
    }
  }

  void _ensureOpen() {
    if (_closed) throw const McpConnectionException('树莓派连接已断开');
  }

  void _ensureInitialized() {
    _ensureOpen();
    if (!_initialized) {
      throw const McpConnectionException('树莓派 MCP 会话尚未初始化');
    }
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json, text/event-stream',
    'MCP-Protocol-Version': ?_protocol,
    'MCP-Session-Id': ?_sessionId,
  };

  Future<Json> _request(String method, Json params) async {
    final id = ++_nextId;
    final reply = (await _send(method, id, params))!;
    _ensureOpen();
    if (reply['jsonrpc'] != '2.0' || reply['id'] != id) {
      throw const McpConnectionException('MCP 响应与请求不匹配');
    }
    if (reply['error'] case final Json error) {
      final message = 'MCP 请求失败（${error['code']}）';
      if (method == 'tools/call') throw FormatException(message);
      throw McpConnectionException(message);
    }
    if (reply['result'] case final Json result) return result;
    throw const McpConnectionException('树莓派 MCP 返回了无效的响应结果');
  }

  Future<Json?> _send(String method, int? id, [Json? params]) async {
    _ensureOpen();
    final abort = Completer<void>();
    _pending.add(abort);
    try {
      final response = await Future.any<Json?>([
        _exchange(method, id, params, abort.future),
        abort.future.then<Json?>(
          (_) => throw const McpConnectionException('树莓派连接已断开'),
        ),
      ]).timeout(method == 'tools/call' ? _toolTimeout : _requestTimeout);
      _ensureOpen();
      return response;
    } on McpConnectionException {
      rethrow;
    } on TimeoutException {
      throw const McpConnectionException('树莓派 MCP 请求超时');
    } on FormatException {
      throw const McpConnectionException('树莓派 MCP 返回了无效的 JSON');
    } catch (_) {
      _ensureOpen();
      throw const McpConnectionException('无法访问树莓派，请检查设备地址和网络');
    } finally {
      _pending.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<Json?> _exchange(
    String method,
    int? id,
    Json? params,
    Future<void> abort,
  ) async {
    final request = http.AbortableRequest('POST', endpoint, abortTrigger: abort)
      ..followRedirects = false
      ..headers.addAll({'Content-Type': 'application/json', ..._headers})
      ..bodyBytes = utf8.encode(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': ?id,
          'method': method,
          'params': ?params,
        }),
      );
    final response = await _http.send(request);
    _ensureOpen();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpConnectionException('树莓派 MCP 请求失败（HTTP ${response.statusCode}）');
    }
    if (method == 'initialize') {
      final sessionId = _header(response, 'mcp-session-id');
      if (sessionId != null && !RegExp(r'^[!-~]+$').hasMatch(sessionId)) {
        throw const McpConnectionException('树莓派返回的 MCP 会话标识无效');
      }
      _sessionId = sessionId;
    }
    if (id == null) {
      await _limited(response.stream).drain<void>();
      return null;
    }
    final type = _header(
      response,
      'content-type',
    )?.split(';').first.trim().toLowerCase();
    if (type == 'text/event-stream') return _readEvent(response.stream, id);
    if (type != 'application/json') {
      throw const McpConnectionException('树莓派 MCP 返回了不兼容的内容类型');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in _limited(response.stream)) {
      bytes.add(chunk);
    }
    return jsonObject(jsonDecode(utf8.decode(bytes.takeBytes())), 'MCP');
  }

  static String? _header(http.StreamedResponse response, String key) => response
      .headers
      .entries
      .where((entry) => entry.key.toLowerCase() == key)
      .firstOrNull
      ?.value;

  static Stream<List<int>> _limited(Stream<List<int>> stream) async* {
    var received = 0;
    await for (final chunk in stream) {
      received += chunk.length;
      if (received > _maxResponseBytes) {
        throw const McpConnectionException('树莓派 MCP 响应超过 1 MiB');
      }
      yield chunk;
    }
  }

  static Future<Json> _readEvent(Stream<List<int>> stream, int id) async {
    final data = <String>[];
    final lines = _limited(stream)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty) {
        if (data.isEmpty) continue;
        final payload = data.join('\n');
        data.clear();
        if (payload.isEmpty) continue;
        final reply = jsonObject(jsonDecode(payload), 'MCP');
        if (reply['id'] == id &&
            (reply.containsKey('result') || reply.containsKey('error'))) {
          return reply;
        }
      } else if (line.startsWith('data:')) {
        final value = line.substring(5);
        data.add(value.startsWith(' ') ? value.substring(1) : value);
      }
    }
    throw const McpConnectionException('树莓派 MCP 响应在返回结果前已中断');
  }
}
