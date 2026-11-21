import 'package:http/http.dart' as http;

import '../network.dart';

class McpClient {
  McpClient(this._http, this.endpoint, this.token);

  final http.Client _http;
  final Uri endpoint;
  final String token;
  static const _supportedVersions = {'2025-11-25', '2025-06-18'};
  String? _protocol;
  int _nextId = 0;

  Future<void> initialize() async {
    final reply = await _request('initialize', {
      'protocolVersion': '2025-11-25',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'PiAgent mobile', 'version': '0.1.0'},
    });
    final version = reply['protocolVersion'];
    if (!_supportedVersions.contains(version)) {
      throw const FormatException('树莓派使用了不兼容的 MCP 协议版本');
    }
    _protocol = version as String;
    await _send('notifications/initialized', null);
  }

  Future<List<Json>> listTools() async {
    final tools = <Json>[];
    String? cursor;
    for (var page = 0; page < 5; page++) {
      final result = await _request('tools/list', {'cursor': ?cursor});
      final entries = result['tools'];
      if (entries is! List) {
        throw const FormatException('树莓派返回的工具清单无效');
      }
      tools.addAll(entries.map((entry) => jsonObject(entry, 'tools')));
      cursor = result['nextCursor'] as String?;
      if (cursor == null) return tools;
    }
    throw const FormatException('树莓派返回的工具清单超过分页上限');
  }

  Future<Json> callTool(String name, Json arguments) async {
    final result = await _request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    final structured = result['structuredContent'];
    if (result['isError'] != true && structured is Json) {
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
    return {'ok': result['isError'] != true, 'output': text};
  }

  Future<Json> _request(String method, Json params) async {
    final id = ++_nextId;
    final reply = (await _send(method, id, params))!;
    if (reply['jsonrpc'] != '2.0' || reply['id'] != id) {
      throw const FormatException('MCP 响应与请求不匹配');
    }
    if (reply['error'] is Json) {
      final error = reply['error'] as Json;
      throw FormatException('MCP 请求失败（${error['code']}）');
    }
    return jsonObject(reply['result'], method);
  }

  Future<Json?> _send(String method, int? id, [Json? params]) => postJson(
    _http,
    endpoint,
    {'jsonrpc': '2.0', 'id': ?id, 'method': method, 'params': ?params},
    {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json, text/event-stream',
      'MCP-Protocol-Version': ?_protocol,
    },
    service: '树莓派 MCP',
    timeout: method == 'tools/call'
        ? const Duration(seconds: 145)
        : const Duration(seconds: 15),
    notification: id == null,
  );
}
