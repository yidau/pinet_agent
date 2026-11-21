import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piagent/agent/agent.dart';
import 'package:piagent/main.dart';
import 'package:piagent/network.dart';
import 'package:piagent/storage/history.dart';

class _EmptyHistory extends History {
  @override
  Future<List<ChatEntry>> load() async => [];

  @override
  Future<void> add(ChatEntry entry) async {}
}

class _DashboardConnection extends Connection {
  _DashboardConnection(this.calls, {this.v07 = false})
    : super(
        Uri.parse('https://pi.example/mcp'),
        'device-token',
        Uri.parse('https://llm.example/chat/completions'),
        '',
        'test-model',
      );

  final List<String> calls;
  final bool v07;
  bool sourceConnected = false;

  Map<String, String> get _domains => {
    'get_capability_status': 'device',
    'get_system_info': 'device',
    'get_access_points': 'wireless_discovery',
    'get_wireless_clients': 'wireless_discovery',
    'get_wifi_channels': 'wireless_discovery',
    'get_signal_history': 'wireless_monitoring',
    'get_wireless_events': 'wireless_monitoring',
    'list_captures': 'packet_analysis',
    'get_capture_metadata': 'packet_analysis',
    if (v07) 'get_bluetooth_devices': 'bluetooth',
    if (v07) 'get_capture_status': 'packet_analysis',
  };

  @override
  http.Client deviceClient() => MockClient((request) async {
    final body = jsonDecode(request.body) as Json;
    final method = body['method'];
    final Json result;
    switch (method) {
      case 'initialize':
        result = {
          'protocolVersion': '2025-11-25',
          'serverInfo': {'name': 'Field Pi', 'version': v07 ? '0.7' : '0.6'},
        };
      case 'notifications/initialized':
        return http.Response('', 202);
      case 'tools/list':
        result = {
          'tools': [
            for (final name in _domains.keys)
              {
                'name': name,
                'description': 'Read $name.',
                'inputSchema': {'type': 'object'},
                'annotations': {'readOnlyHint': true},
              },
          ],
        };
      case 'tools/call':
        final params = body['params'] as Json;
        final name = params['name'] as String;
        calls.add(name);
        final Json data;
        switch (name) {
          case 'get_capability_status':
            data = {
              'kismet': {
                'installed': true,
                'running': true,
                'version': 'test-build',
                'datasource_count': sourceConnected ? 1 : 0,
                'wireless_status': sourceConnected ? 'AVAILABLE' : 'DEGRADED',
                'reason': sourceConnected
                    ? ''
                    : 'No supported wireless capture source',
                if (v07)
                  'source_states': {
                    'managed_scan': {
                      'status': sourceConnected ? 'AVAILABLE' : 'DEGRADED',
                      'reason': sourceConnected ? '' : 'Managed scan inactive',
                    },
                    'monitor_mode': {
                      'status': 'DEGRADED',
                      'reason': 'No monitor source',
                    },
                    'bluetooth_scan': {
                      'status': sourceConnected ? 'AVAILABLE' : 'UNAVAILABLE',
                      'reason': sourceConnected
                          ? ''
                          : 'Bluetooth helper missing',
                    },
                    'pcap_replay': {'status': 'AVAILABLE', 'reason': ''},
                  },
              },
              'capabilities': [
                for (final entry in _domains.entries)
                  {
                    'name': entry.key,
                    'status':
                        entry.value == 'device' ||
                            (v07 && entry.value == 'packet_analysis') ||
                            (v07 &&
                                sourceConnected &&
                                entry.key == 'get_bluetooth_devices') ||
                            (sourceConnected &&
                                entry.key == 'get_access_points')
                        ? 'AVAILABLE'
                        : entry.value.startsWith('wireless')
                        ? 'DEGRADED'
                        : 'UNAVAILABLE',
                    'domain': entry.value,
                  },
              ],
            };
          case 'get_system_info':
            data = {
              'hostname': 'field-pi',
              'architecture': 'aarch64',
              'os': 'Ubuntu',
              'kernel': 'test-kernel',
            };
          case 'get_access_points':
            data = {
              'access_points': [
                {
                  'ssid': 'Test-lab',
                  'rssi_dbm': -52,
                  'channel': '36',
                  if (v07) 'observation_source': 'managed_scan',
                  if (v07) 'kismet_reported': false,
                },
              ],
            };
          case 'get_bluetooth_devices':
            data = {
              'devices': [
                {
                  'name': 'Lab beacon',
                  'address': '02:00:00:00:00:01',
                  'rssi_dbm': -61,
                  'observation_source': 'bluetooth_scan',
                },
              ],
            };
          case 'list_captures':
            data = {
              'captures': [
                {
                  'id': 'sample.pcapng',
                  'filename': 'sample.pcapng',
                  'size_bytes': 2048,
                  'format': 'pcapng',
                  'modified_at': '2026-11-21T13:00:00Z',
                },
              ],
            };
          case 'get_capture_status':
            data = {
              'state': 'running',
              'filename': 'sample.pcapng',
              'datasource': 'lab-replay',
            };
          case 'get_capture_metadata':
            expect(params['arguments'], {'capture_id': 'sample.pcapng'});
            data = {
              'filename': 'sample.pcapng',
              'size_bytes': 2048,
              'format': 'pcapng',
              'modified_at': '2026-11-21T13:00:00Z',
            };
          default:
            throw StateError('Unexpected MCP tool $name');
        }
        result = {'structuredContent': data};
      default:
        throw StateError('Unexpected MCP method $method');
    }
    return http.Response(
      jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Finder _tab(String label) => find.widgetWithText(NavigationDestination, label);

Future<void> _phoneLayout(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 780));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets(
    'C7: shows distinct radio sources, metadata and replay state from mock MCP',
    (tester) async {
      await _phoneLayout(tester);
      final calls = <String>[];
      final connection = _DashboardConnection(calls, v07: true);
      await tester.pumpWidget(
        PiAgentApp(history: _EmptyHistory(), initialConnection: connection),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设备'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设备能力（11）'));
      await tester.pumpAndSettle();
      for (final label in [
        'Wi-Fi Managed Scan · 条件不足',
        'Wi-Fi Monitor Mode · 条件不足',
        'Bluetooth Active Scan · 未实现',
        'PCAP Replay · 可用',
        'No monitor source',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      connection.sourceConnected = true;
      await tester.tap(_tab('Wireless'));
      await tester.pumpAndSettle();
      expect(find.text('Wi-Fi Networks'), findsOneWidget);
      expect(find.text('Managed Scan'), findsOneWidget);
      expect(find.text('扫描报告未写入 Kismet'), findsOneWidget);
      expect(find.text('未知'), findsOneWidget);
      expect(find.text('Test-lab'), findsOneWidget);
      expect(find.text('Bluetooth Devices'), findsOneWidget);
      expect(find.text('Lab beacon'), findsOneWidget);
      expect(find.textContaining('Active Scan ·'), findsOneWidget);
      await tester.tap(_tab('Captures'));
      await tester.pumpAndSettle();
      expect(find.text('lab-replay'), findsOneWidget);
      expect(find.text('running'), findsOneWidget);
      expect(find.textContaining('pcapng · 2.0 KiB'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'sample.pcapng'));
      await tester.pumpAndSettle();
      expect(find.text('文件元信息'), findsOneWidget);
      expect(find.text('2.0 KiB'), findsOneWidget);
      expect(calls.last, 'get_capture_metadata');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'displays Kismet, degraded wireless and refreshed AP observations (F1–F3)',
    (tester) async {
      await _phoneLayout(tester);
      final calls = <String>[];
      final connection = _DashboardConnection(calls);
      await tester.pumpWidget(
        PiAgentApp(history: _EmptyHistory(), initialConnection: connection),
      );
      await tester.pumpAndSettle();

      expect(find.text('PocketNet AI'), findsOneWidget);
      expect(find.text('未连接'), findsOneWidget);
      for (final label in ['Overview', 'Wireless', 'Captures', 'AI']) {
        expect(_tab(label), findsOneWidget);
      }

      await tester.tap(find.text('连接设备'));
      await tester.pumpAndSettle();
      expect(find.text('已连接'), findsOneWidget);
      expect(calls, ['get_capability_status', 'get_system_info']);

      await tester.tap(find.text('设备能力（9）'));
      await tester.pumpAndSettle();
      expect(find.text('Kismet 观测引擎'), findsOneWidget);
      expect(find.text('数据源 0'), findsOneWidget);
      expect(find.text('运行中'), findsOneWidget);
      expect(find.text('版本 test-build'), findsOneWidget);
      expect(find.text('无线观测 · 条件不足'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(_tab('Wireless'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Wireless monitoring is degraded: no supported capture source is available.',
        ),
        findsOneWidget,
      );
      expect(find.text('已连接'), findsOneWidget);
      expect(calls, [
        'get_capability_status',
        'get_system_info',
        'get_capability_status',
      ]);

      connection.sourceConnected = true;
      await tester.tap(_tab('Wireless'));
      await tester.pumpAndSettle();
      expect(find.text('Test-lab'), findsOneWidget);
      expect(find.text('-52 dBm'), findsOneWidget);
      expect(calls.last, 'get_access_points');

      await tester.tap(_tab('Captures'));
      await tester.pumpAndSettle();
      expect(find.text('报文采集尚未实现'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);

      await tester.tap(_tab('AI'));
      await tester.pumpAndSettle();
      expect(find.text('AI 调查'), findsOneWidget);
      expect(find.byTooltip('发送消息'), findsOneWidget);

      await tester.tap(_tab('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('已连接'), findsOneWidget);
      expect(calls.where((name) => name == 'get_system_info'), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps the offline AI prompt and device settings', (
    tester,
  ) async {
    await _phoneLayout(tester);
    await tester.pumpWidget(PiAgentApp(history: _EmptyHistory()));
    await tester.pumpAndSettle();
    await tester.tap(_tab('AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看网络状态'));
    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.controller?.text, contains('网络信息'));
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pumpAndSettle();
    expect(find.text(Agent.disconnectedReply), findsOneWidget);
    await tester.tap(find.text('连接设备'));
    await tester.pumpAndSettle();
    expect(find.text('树莓派 MCP 地址'), findsOneWidget);
    expect(find.text('使用此连接'), findsOneWidget);
    expect(find.text('测试树莓派连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
