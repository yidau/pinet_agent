import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:piagent/agent/agent.dart';
import 'package:piagent/llm/llm_client.dart';
import 'package:piagent/mcp/device_connection.dart';
import 'package:piagent/mcp/tool_registry.dart';
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
  bool reportsCapabilities = true,
  Map<String, String> statuses = const {},
  Future<Json> Function()? onCapabilities,
}) {
  const id = 'pi-session';
  const protocol = '2025-11-25';
  final advertised = [
    ...tools,
    if (reportsCapabilities) _tool('get_capability_status'),
  ];
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
        result = {'tools': advertised};
      case 'tools/call':
        final name = (body['params'] as Json)['name'] as String;
        calls?.add(name);
        result = switch (name) {
          'get_capability_status' => {
            'structuredContent': onCapabilities == null
                ? {
                    'capabilities': [
                      for (final tool in advertised)
                        {
                          'name': tool['name'],
                          'status': statuses[tool['name']] ?? 'AVAILABLE',
                          'domain': tool['name'] == 'get_access_points'
                              ? 'wireless_discovery'
                              : 'device',
                        },
                    ],
                  }
                : await onCapabilities(),
          },
          'get_system_info' => {
            'structuredContent': {'hostname': 'workshop'},
          },
          'get_kismet_status' => {
            'structuredContent': {'running': true, 'version': 'test-build'},
          },
          'get_network_status' => {
            'structuredContent': {'interface': 'wlan0', 'state': 'online'},
          },
          _ => {
            'isError': true,
            'structuredContent': {
              'status': 'unavailable',
              'error_code': 'CAPABILITY_NOT_IMPLEMENTED',
              'message': 'Radio unavailable',
              'data': null,
            },
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
  test('Agent reads Kismet and explains missing AP source using the current report (F4–F6)', () async {
    final device = DeviceConnection();
    addTearDown(device.dispose);
    var sourceActive = true;
    final calls = <String>[];
    const missingSource = 'No supported wireless capture source';
    await _connect(
      device,
      _deviceClient(
        [_tool('get_kismet_status'), _tool('get_access_points')],
        calls: calls,
        onCapabilities: () async => {
          'kismet': {
            'running': true,
            'datasource_count': sourceActive ? 1 : 0,
            'wireless_status': sourceActive ? 'AVAILABLE' : 'DEGRADED',
          },
          'capabilities': [
            {'name': 'get_capability_status', 'status': 'AVAILABLE'},
            {'name': 'get_kismet_status', 'status': 'AVAILABLE'},
            {
              'name': 'get_access_points',
              'status': sourceActive ? 'AVAILABLE' : 'DEGRADED',
              if (!sourceActive) 'reason': missingSource,
            },
          ],
        },
      ),
    );
    sourceActive = false;
    var rounds = 0;
    final cloud = MockClient((request) async {
      final body = jsonDecode(request.body) as Json;
      expect(
        (body['tools'] as List).map((t) => t['function']['name']),
        unorderedEquals(['get_kismet_status', 'get_capability_status']),
      );
      if (rounds++ == 0) {
        return _json(
          _reply({
            'tool_calls': [
              _call('get_kismet_status', {}),
              _call('get_capability_status', {}),
            ],
          }),
        );
      }
      final evidence = (body['messages'] as List)
          .where((m) => m['role'] == 'tool')
          .map((m) => jsonDecode(m['content'] as String) as Json)
          .toList();
      expect(evidence.first['running'], isTrue);
      expect(
        (evidence.last['capabilities'] as List).last['reason'],
        missingSource,
      );
      return _json(_reply({'content': 'Kismet 正在运行。缺少采集源，无法列出接入点。'}));
    });
    addTearDown(cloud.close);
    final result = await Agent(
      device.session,
      _llm(cloud),
    ).run('查询 Kismet 和附近的 AP', onEvent: (_) {});
    expect(calls, [
      'get_capability_status',
      'get_capability_status',
      'get_kismet_status',
      'get_capability_status',
    ]);
    expect(result, contains('缺少采集源'));
  });

  test('discovers all capabilities and offers only available read-only tools (F2–F5, R5)', () async {
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
      _deviceClient(
        [
          _tool('get_system_info'),
          _tool('get_network_status', schema: networkSchema),
          _tool('get_radio.status'),
          _tool('get_access_points'),
          _tool('get_arp_neighbors'),
          _tool('analyze_packet_capture'),
          _tool('write_file'),
          _tool('execute_shell'),
          {
            ..._tool('update_device'),
            'annotations': {'readOnlyHint': false},
          },
        ],
        calls: calls,
        statuses: const {
          'get_access_points': 'UNAVAILABLE',
          'get_arp_neighbors': 'DEGRADED',
          'analyze_packet_capture': 'ERROR',
        },
      ),
    );
    final session = device.session!;
    expect(session.registry.tools, hasLength(10));
    expect(session.registry['get_access_points']?.domain, 'wireless_discovery');
    expect(
      session.registry['get_access_points']?.status,
      CapabilityStatus.unavailable,
    );
    expect(
      session.registry['get_arp_neighbors']?.status,
      CapabilityStatus.degraded,
    );
    expect(
      session.registry['analyze_packet_capture']?.status,
      CapabilityStatus.error,
    );
    await expectLater(
      session.callTool('get_access_points', {}),
      throwsFormatException,
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
        'get_capability_status',
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
              _call('get_access_points', {}),
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
            .take(4)
            .every((message) => jsonDecode(message['content'])['ok'] == false),
        isTrue,
      );
      expect(messages.last['content'], contains('Radio unavailable'));
      expect(
        jsonDecode(messages.last['content'])['error_code'],
        'CAPABILITY_NOT_IMPLEMENTED',
      );
      expect(jsonDecode(messages.last['content'])['status'], 'unavailable');
      return _json(_reply({'content': '网卡 wlan0 在线，无线电数据暂不可用。'}));
    });
    addTearDown(cloud.close);

    final events = <ToolEvent>[];
    final answer = await Agent(
      device.session,
      _llm(cloud),
    ).run('查看设备和网络状态', onEvent: events.add);
    expect(calls, [
      'get_capability_status',
      'get_system_info',
      'get_network_status',
      'get_radio.status',
    ]);
    expect(events.last.failed, isTrue);
    expect(
      events.any(
        (event) => event.output?.contains('"hostname": "workshop"') ?? false,
      ),
      isTrue,
    );
    expect(answer, contains('wlan0'));
    expect(device.status, DeviceConnectionStatus.ready);
    expect(
      await Agent(null, _llm(cloud)).run('查看设备状态', onEvent: events.add),
      Agent.disconnectedReply,
    );
    expect(turns, 2);
  });

  test(
    'connects, disconnects, and rediscovers tool availability (F1–F3, F6)',
    () async {
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
      expect(
        first.registry['get_system_info']?.status,
        CapabilityStatus.available,
      );
      await device.disconnect();
      expect(device.status, DeviceConnectionStatus.disconnected);
      expect(device.session, isNull);
      expect(first.isActive, isFalse);
      expect(methods, [
        'initialize',
        'notifications/initialized',
        'tools/list',
        'tools/call',
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
        _deviceClient(
          [_tool('get_system_info'), _tool('get_wireless_observations')],
          methods: methods,
          statuses: const {'get_system_info': 'DEGRADED'},
        ),
      );
      expect(
        device.session!.registry['get_system_info']?.status,
        CapabilityStatus.degraded,
      );
      expect(
        device.session!.registry['get_wireless_observations']?.isCallable,
        isTrue,
      );
      expect(methods.where((method) => method == 'tools/list'), hasLength(2));
      expect(methods.where((method) => method == 'tools/call'), hasLength(2));
    },
  );

  test(
    'disconnect invalidates capability discovery still in flight (F3, F6)',
    () async {
      final device = DeviceConnection();
      addTearDown(device.dispose);
      final capabilities = Completer<Json>();
      final started = Completer<void>();
      final connecting = _connect(
        device,
        _deviceClient(
          [],
          onCapabilities: () {
            started.complete();
            return capabilities.future;
          },
        ),
      );
      await started.future;
      expect(device.status, DeviceConnectionStatus.discovering);
      await device.disconnect();
      capabilities.complete({
        'capabilities': [
          {
            'name': 'get_capability_status',
            'status': 'AVAILABLE',
            'domain': 'device',
          },
        ],
      });
      await connecting;
      expect(device.status, DeviceConnectionStatus.disconnected);
      expect(device.session, isNull);
    },
  );

  test('requires status names to match the catalog and shows unknown for older servers (F3–F5)', () async {
    final device = DeviceConnection();
    addTearDown(device.dispose);
    await _connect(
      device,
      _deviceClient(
        [_tool('get_system_info')],
        onCapabilities: () async => {
          'capabilities': [
            {
              'name': 'get_capability_status',
              'status': 'AVAILABLE',
              'domain': 'device',
            },
            {
              'name': 'get_access_points',
              'status': 'AVAILABLE',
              'domain': 'wireless_discovery',
            },
          ],
        },
      ),
    );
    expect(device.status, DeviceConnectionStatus.error);
    expect(device.session, isNull);

    await _connect(
      device,
      _deviceClient([_tool('get_system_info')], reportsCapabilities: false),
    );
    expect(device.status, DeviceConnectionStatus.ready);
    expect(
      device.session?.registry['get_system_info']?.status,
      CapabilityStatus.unknown,
    );
    expect(device.session?.registry.callableTools, isEmpty);
  });
}
