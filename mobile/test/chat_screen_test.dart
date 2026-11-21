import 'dart:async';
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
  _DashboardConnection(
    this.calls, {
    this.v07 = false,
    this.phoneControl = false,
  }) : super(
         Uri.parse('https://pi.example/mcp'),
         'device-token',
         Uri.parse('https://llm.example/chat/completions'),
         '',
         'test-model',
       );

  final List<String> calls;
  final bool v07;
  final bool phoneControl;
  bool sourceConnected = false;
  Future<void>? bluetoothReadDelay;
  Json? accessPointsReply;
  Json? apDetailsReply;

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
    if (v07) 'get_ap_details': 'wireless_discovery',
    if (v07) 'get_capture_status': 'packet_analysis',
  };

  @override
  http.Client deviceClient() => MockClient((request) async {
    if (request.url.path.startsWith('/operator/')) {
      expect(phoneControl, isTrue);
      expect(request.headers['Authorization'], 'Bearer device-token');
      final action = request.url.path;
      calls.add('${request.method} $action');
      if (action == '/operator/radio/wifi-scan') sourceConnected = true;
      return http.Response(
        jsonEncode({
          'wifi': {
            'state': sourceConnected ? 'completed' : 'idle',
            'access_point_count': sourceConnected ? 1 : 0,
          },
          'bluetooth': {'state': 'idle'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
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
                'inputSchema': name == 'get_ap_details'
                    ? {
                        'type': 'object',
                        'properties': {
                          'ap_id': {'type': 'string'},
                        },
                        'required': ['ap_id'],
                      }
                    : {'type': 'object'},
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
              if (phoneControl) 'operator_api': 1,
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
                                const {
                                  'get_access_points',
                                  'get_ap_details',
                                }.contains(entry.key))
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
            data =
                accessPointsReply ??
                {
                  'access_points': [
                    {
                      'id': 'ap-test',
                      'bssid': '02:00:00:00:00:02',
                      'observed_at': 1770000000,
                      'frequency_mhz': 5180,
                      'ssid': 'Test-lab',
                      'rssi_dbm': -52,
                      'channel': '36',
                      if (v07) 'observation_source': 'managed_scan',
                      if (v07) 'kismet_reported': false,
                    },
                  ],
                };
          case 'get_ap_details':
            expect(params['arguments'], {'ap_id': 'ap-test'});
            data =
                apDetailsReply ??
                {
                  'access_point': {
                    'id': 'ap-test',
                    'ssid': 'Test-lab',
                    'security': '[RSN-SAE-CCMP][ESS]',
                  },
                  'source': 'managed_scan',
                };
          case 'get_bluetooth_devices':
            if (bluetoothReadDelay case final delay?) await delay;
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
    'only an explicit phone tap starts a scan and refreshes observations',
    (tester) async {
      await _phoneLayout(tester);
      final calls = <String>[];
      final connection = _DashboardConnection(
        calls,
        v07: true,
        phoneControl: true,
      );
      await tester.pumpWidget(
        PiAgentApp(history: _EmptyHistory(), initialConnection: connection),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设备'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('无线'));
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.startsWith('POST /operator/')),
        isEmpty,
      );
      await tester.tap(find.text('扫描 Wi-Fi'));
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call.startsWith('POST /operator/')),
        isEmpty,
      );
      await tester.tap(find.text('确认扫描'));
      await tester.pumpAndSettle();
      expect(
        calls.where((call) => call == 'POST /operator/radio/wifi-scan'),
        hasLength(1),
      );
      expect(calls, contains('get_access_points'));
      expect(find.textContaining('1 个接入点'), findsOneWidget);
    },
  );
  testWidgets(
    'C7: shows distinct radio sources, metadata and replay state from mock MCP',
    (tester) async {
      await _phoneLayout(tester);
      final calls = <String>[];
      final connection = _DashboardConnection(calls, v07: true)
        ..accessPointsReply = {
          'access_points': [
            for (final (mac, id, signal, time) in [
              ('02:00:00:00:00:02', 'old-ap-id', -82, 1770000000),
              ('02:00:00:00:00:02', 'ap-test', -52, 1770000060),
              ('02:00:00:00:00:03', 'second-bssid', -68, 1770000060),
            ])
              {
                'id': id,
                'mac': mac,
                'name': 'Test-lab',
                'channel': '36',
                'rssi_dbm': signal,
                'observed_at': time,
                'observation_source': 'managed_scan',
                'kismet_reported': false,
              },
          ],
        };
      await tester.pumpWidget(
        PiAgentApp(history: _EmptyHistory(), initialConnection: connection),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设备'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设备能力（12）'));
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
      connection.sourceConnected = true;
      await tester.tap(find.byTooltip('刷新设备能力'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(_tab('无线'));
      await tester.pumpAndSettle();
      expect(find.text('附近网络'), findsOneWidget);
      await tester.ensureVisible(find.text('Test-lab'));
      expect(find.text('Test-lab'), findsOneWidget);
      await tester.tap(find.text('Test-lab'));
      await tester.pumpAndSettle();
      final bssid = find.text('02:00:00:00:00:02');
      expect(bssid, findsOneWidget);
      expect(find.text('02:00:00:00:00:03'), findsOneWidget);
      await tester.ensureVisible(bssid);
      await tester.tap(bssid);
      await tester.pumpAndSettle();
      expect(find.text('观测历史'), findsOneWidget);
      expect(find.textContaining('WPA3'), findsWidgets);
      expect(calls, contains('get_ap_details'));
      await tester.scrollUntilVisible(
        find.text('扫描报告未写入 Kismet'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('客户端').first);
      await tester.tap(find.text('客户端').first);
      await tester.pumpAndSettle();
      expect(find.text('暂无客户端记录'), findsOneWidget);
      await tester.tap(find.text('蓝牙').first);
      await tester.pumpAndSettle();
      expect(find.text('蓝牙设备'), findsOneWidget);
      expect(find.text('Lab beacon'), findsOneWidget);
      expect(find.text('Bluetooth Active Scan'), findsWidgets);
      await tester.tap(_tab('采集'));
      await tester.pumpAndSettle();
      expect(find.text('lab-replay'), findsOneWidget);
      expect(find.text('进行中'), findsWidgets);
      await tester.tap(find.text('PCAP 文件').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('2.0 KiB'), findsWidgets);
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
      for (final label in ['概览', '无线', '采集', 'AI 助手']) {
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

      await tester.tap(_tab('无线'));
      await tester.pumpAndSettle();
      expect(find.text('暂无网络记录'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(calls, isNot(contains('get_access_points')));

      connection.sourceConnected = true;
      await tester.tap(find.text('设备能力（9）'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刷新设备能力'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Test-lab'), findsOneWidget);
      expect(find.textContaining('-52 dBm'), findsWidgets);
      expect(calls.last, 'get_access_points');

      await tester.tap(_tab('采集'));
      await tester.pumpAndSettle();
      expect(find.text('实时采集'), findsOneWidget);
      await tester.tap(find.text('PCAP 文件').first);
      await tester.pumpAndSettle();
      expect(find.text('文件库暂不可用'), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);

      await tester.tap(_tab('AI 助手'));
      await tester.pumpAndSettle();
      expect(find.text('调查当前网络'), findsOneWidget);
      expect(find.byTooltip('发送消息'), findsOneWidget);

      await tester.tap(_tab('概览'));
      await tester.pumpAndSettle();
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('field-pi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a network opens its distinct BSSIDs and a single AP observation history',
    (tester) async {
      await _phoneLayout(tester);
      const first = '02:00:00:00:00:02';
      const second = '02:00:00:00:00:03';
      const start = 1770000000;
      const ap = {
        'id': 'ap-test',
        'ssid': 'Cafe',
        'bssid': first,
        'channel': '11',
        'rssi_dbm': -46,
        'observation_source': 'managed_scan',
        'observation_sources': ['managed_scan', 'monitor_mode'],
        'first_seen': start,
        'last_seen': start + 10,
      };
      final calls = <String>[];
      final connection = _DashboardConnection(calls, v07: true)
        ..sourceConnected = true
        ..accessPointsReply = {
          'network_count': 1,
          'bssid_count': 2,
          'channel_count': 2,
          'access_points': [
            ap,
            {
              ...ap,
              'id': 'second',
              'bssid': second,
              'channel': '36',
              'rssi_dbm': -65,
            },
          ],
          'networks': [
            {
              'ssid': 'Cafe',
              'bssids': [first, second],
              'bssid_count': 2,
              'channel_count': 2,
              'security_modes': [],
              'strongest_rssi_dbm': -46,
              'weakest_rssi_dbm': -65,
              'last_seen': start + 10,
            },
          ],
        }
        ..apDetailsReply = {
          'access_point': ap,
          'observations': [
            {
              'timestamp': start,
              'rssi_dbm': -77,
              'channel': '6',
              'observation_source': 'monitor_mode',
            },
            {
              'timestamp': start + 10,
              'rssi_dbm': -46,
              'channel': '11',
              'observation_source': 'managed_scan',
            },
          ],
        };
      await tester.pumpWidget(
        PiAgentApp(history: _EmptyHistory(), initialConnection: connection),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('连接设备'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('无线'));
      await tester.pumpAndSettle();
      final cafe = find.text('Cafe');
      await tester.scrollUntilVisible(
        cafe,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(cafe, findsOneWidget);
      await tester.tap(cafe);
      await tester.pumpAndSettle();
      expect(find.text(first), findsOneWidget);
      expect(find.text(second), findsOneWidget);
      await tester.tap(find.text(first));
      await tester.pumpAndSettle();
      expect(find.text('观测历史'), findsOneWidget);
      expect(calls.where((name) => name == 'get_ap_details'), hasLength(1));
      await tester.scrollUntilVisible(
        find.textContaining('Monitor Mode · -77 dBm'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Monitor Mode · -77 dBm'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('接入点'));
      await tester.tap(find.text('接入点'));
      await tester.pumpAndSettle();
      expect(find.text(first), findsOneWidget);
      await tester.ensureVisible(find.text('信道'));
      await tester.tap(find.text('信道'));
      await tester.pumpAndSettle();
      expect(find.text('信道 11'), findsOneWidget);
      expect(find.text('信道 36'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('revisiting tabs retains the selected view and observed rows', (
    tester,
  ) async {
    await _phoneLayout(tester);
    final calls = <String>[];
    final connection = _DashboardConnection(calls, v07: true)
      ..sourceConnected = true;
    await tester.pumpWidget(
      PiAgentApp(history: _EmptyHistory(), initialConnection: connection),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接设备'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('无线'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('蓝牙').first);
    await tester.pumpAndSettle();
    expect(find.text('Lab beacon'), findsOneWidget);

    await tester.tap(_tab('采集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PCAP 文件').first);
    await tester.pumpAndSettle();
    final file = find.widgetWithText(ListTile, 'sample.pcapng');
    expect(file, findsOneWidget);

    final beforeReturn = List.of(calls);
    await tester.tap(_tab('无线'));
    await tester.pump();
    expect(find.text('Lab beacon'), findsOneWidget);
    await tester.tap(_tab('采集'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(file, findsOneWidget);
    await tester.tap(_tab('无线'));
    await tester.pumpAndSettle();
    await tester.tap(_tab('无线'));
    await tester.pumpAndSettle();
    expect(find.text('Lab beacon'), findsOneWidget);
    expect(calls, beforeReturn);

    final delayed = Completer<void>();
    connection.bluetoothReadDelay = delayed.future;
    await tester.tap(find.text('设备能力（12）'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新设备能力'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      calls.where((name) => name == 'get_bluetooth_devices'),
      hasLength(2),
    );
    expect(find.text('Lab beacon'), findsOneWidget);
    expect(find.text('暂无蓝牙观测'), findsNothing);
    delayed.complete();
    await tester.pumpAndSettle();

    await tester.tap(_tab('采集'));
    await tester.pumpAndSettle();
    expect(file, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all workspaces fit compact dark and wide light layouts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(PiAgentApp(history: _EmptyHistory()));
    await tester.pumpAndSettle();
    for (final size in [const Size(320, 620), const Size(800, 720)]) {
      if (size.width == 800) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('设备与外观设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('切换浅色外观'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(_tab('概览'))).brightness,
          Brightness.light,
        );
      }
      for (final tab in ['概览', '无线', '采集', 'AI 助手']) {
        await tester.tap(_tab(tab));
        await tester.pumpAndSettle();
        expect(find.text('连接设备'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size / $tab');
      }
    }
  });

  testWidgets('keeps the offline AI prompt and device settings', (
    tester,
  ) async {
    await _phoneLayout(tester);
    await tester.pumpWidget(PiAgentApp(history: _EmptyHistory()));
    await tester.pumpAndSettle();
    await tester.tap(_tab('AI 助手'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看网络状态'));
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
