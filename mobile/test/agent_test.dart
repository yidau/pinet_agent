import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:piagent/agent/agent.dart';
import 'package:piagent/llm/llm_client.dart';
import 'package:piagent/mcp/device_connection.dart';
import 'package:piagent/network.dart';

final _endpoint = Uri.parse('https://pi.example/mcp');

http.Response _json(Json payload) => http.Response.bytes(
  utf8.encode(jsonEncode(payload)),
  200,
  headers: {'Content-Type': 'application/json'},
);

Json _tool(String name, {Json? schema}) => {
  'name': name,
  'description': '查询 $name',
  'inputSchema': schema ?? {'type': 'object', 'additionalProperties': false},
  'annotations': {'readOnlyHint': true},
};

Json _reply(Json message) => {
  'choices': [
    {'message': message},
  ],
};

Json _call(String name, Json arguments) => {
  'id': name,
  'type': 'function',
  'function': {'name': name, 'arguments': jsonEncode(arguments)},
};

LlmClient _llm(http.Client client) => LlmClient(
  client,
  Uri.parse('https://llm.example/chat'),
  'llm-key',
  'model',
);

Future<void> _connect(DeviceConnection device, http.Client client) =>
    device.connect(
      endpoint: _endpoint,
      token: 'device-token',
      createHttpClient: () => client,
    );

MockClient _deviceClient(
  List<Json> tools, {
  List<String>? methods,
  List<String>? calls,
  bool stateful = false,
  Future<Json> Function()? onList,
}) {
  const id = 'pi-session';
  const protocol = '2025-11-25';
  return MockClient((request) async {
    expect(request.headers['Authorization'], 'Bearer device-token');
    if (request.method == 'DELETE') {
      expect(request.headers['Mcp-Session-Id'], id);
      methods?.add('DELETE');
      return http.Response('', 204);
    }
    final body = jsonDecode(request.body) as Json;
    final method = body['method'] as String;
    methods?.add(method);
    if (method != 'initialize') {
      expect(request.headers['MCP-Protocol-Version'], protocol);
      if (stateful) expect(request.headers['Mcp-Session-Id'], id);
    }
    if (method == 'notifications/initialized') return http.Response('', 202);
    Json result;
    switch (method) {
      case 'initialize':
        result = {
          'protocolVersion': protocol,
          'serverInfo': {'name': 'Workshop Pi', 'version': '1'},
        };
      case 'tools/list':
        result = onList == null ? {'tools': tools} : await onList();
      case 'tools/call':
        final name = (body['params'] as Json)['name'] as String;
        calls?.add(name);
        result = switch (name) {
          'get_system_info' => {
            'structuredContent': {'hostname': 'workshop'},
          },
          'get_network_status' => {
            'structuredContent': {'interface': 'wlan0', 'state': 'online'},
          },
          _ => {
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'Radio unavailable'},
            ],
          },
        };
      default:
        throw StateError('Unexpected MCP method $method');
    }
    final reply = _json({'jsonrpc': '2.0', 'id': body['id'], 'result': result});
    if (!stateful || method != 'initialize') return reply;
    return http.Response.bytes(
      reply.bodyBytes,
      200,
      headers: {...reply.headers, 'Mcp-Session-Id': id},
    );
  });
}

void main() {
  test(
    'discovers and calls only current read-only validated tools (M1–M3, A1–A4)',
    () async {
      final device = DeviceConnection();
      addTearDown(device.dispose);
      final calls = <String>[];
      final networkSchema = <String, dynamic>{
        'type': 'object',
        'properties': {
          'interface': {'type': 'string', 'minLength': 1},
        },
        'required': ['interface'],
        'additionalProperties': false,
      };
      await _connect(
        device,
        _deviceClient([
          _tool('get_system_info'),
          _tool('get_network_status', schema: networkSchema),
          _tool('get_radio.status'),
          _tool('write_file'),
          _tool('execute_shell'),
          {
            ..._tool('update_device'),
            'annotations': {'readOnlyHint': false},
          },
        ], calls: calls),
      );

      var turns = 0;
      final cloud = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer llm-key');
        expect(request.body, isNot(contains('device-token')));
        final body = jsonDecode(request.body) as Json;
        final advertised = (body['tools'] as List).map(
          (item) => item['function'],
        );
        final radioName =
            advertised.singleWhere(
                  (item) => item['description'] == '查询 get_radio.status',
                )['name']
                as String;
        expect(radioName, isNot(contains('.')));
        expect(advertised.map((item) => item['name']).toSet(), {
          'get_system_info',
          'get_network_status',
          radioName,
        });
        expect(
          advertised.singleWhere(
            (item) => item['name'] == 'get_network_status',
          )['parameters'],
          networkSchema,
        );
        if (turns++ == 0) {
          return _json(
            _reply({
              'tool_calls': [
                _call('get_unknown_observation', {}),
                _call('write_file', {}),
                _call('get_network_status', {'interface': 42}),
                _call('get_system_info', {}),
                _call('get_network_status', {'interface': 'wlan0'}),
                _call(radioName, {}),
              ],
            }),
          );
        }
        final messages = (body['messages'] as List)
            .where((message) => message['role'] == 'tool')
            .toList();
        expect(
          messages
              .take(3)
              .every(
                (message) => jsonDecode(message['content'])['ok'] == false,
              ),
          isTrue,
        );
        expect(messages.last['content'], contains('Radio unavailable'));
        return _json(_reply({'content': '网卡 wlan0 在线，无线电数据暂不可用。'}));
      });
      addTearDown(cloud.close);

      final events = <ToolEvent>[];
      final answer = await Agent(
        device.session,
        _llm(cloud),
      ).run('查看设备和网络状态', onEvent: events.add);
      expect(calls, [
        'get_system_info',
        'get_network_status',
        'get_radio.status',
      ]);
      expect(events.last.failed, isTrue);
      expect(answer, contains('wlan0'));
      expect(device.status, DeviceConnectionStatus.ready);
      expect(
        await Agent(null, _llm(cloud)).run('查看设备状态', onEvent: events.add),
        Agent.disconnectedReply,
      );
      expect(turns, 2);
    },
  );

  test('disconnects, reports unavailability, and rediscovers on reconnect (C1–C4, M4–M5)', () async {
    final device = DeviceConnection();
    addTearDown(device.dispose);
    final statuses = <DeviceConnectionStatus>[];
    device.addListener(() => statuses.add(device.status));
    final methods = <String>[];
    await _connect(
      device,
      _deviceClient(
        [_tool('get_system_info')],
        methods: methods,
        stateful: true,
      ),
    );
    expect(statuses, [
      DeviceConnectionStatus.connecting,
      DeviceConnectionStatus.discovering,
      DeviceConnectionStatus.ready,
    ]);
    expect(device.deviceName, 'Workshop Pi');
    final first = device.session!;
    await device.disconnect();
    expect(device.status, DeviceConnectionStatus.disconnected);
    expect(device.session, isNull);
    expect(first.isActive, isFalse);
    expect(methods, [
      'initialize',
      'notifications/initialized',
      'tools/list',
      'DELETE',
    ]);

    await _connect(
      device,
      MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(device.status, DeviceConnectionStatus.error);
    expect(device.session, isNull);
    expect(device.error, isNotEmpty);

    await _connect(
      device,
      _deviceClient([_tool('get_wireless_observations')], methods: methods),
    );
    expect(
      device.session!.registry.tools.single.name,
      'get_wireless_observations',
    );
    expect(methods.where((method) => method == 'tools/list'), hasLength(2));
  });

  test('disconnect invalidates discovery still in flight (C2, M4)', () async {
    final device = DeviceConnection();
    addTearDown(device.dispose);
    final listing = Completer<Json>();
    final started = Completer<void>();
    final connecting = _connect(
      device,
      _deviceClient(
        [],
        onList: () {
          started.complete();
          return listing.future;
        },
      ),
    );
    await started.future;
    expect(device.status, DeviceConnectionStatus.discovering);
    await device.disconnect();
    listing.complete({
      'tools': [_tool('get_system_info')],
    });
    await connecting;
    expect(device.status, DeviceConnectionStatus.disconnected);
    expect(device.session, isNull);
  });
}
