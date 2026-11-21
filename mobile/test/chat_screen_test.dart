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
  _DashboardConnection(this.calls)
    : super(
        Uri.parse('https://pi.example/mcp'),
        'device-token',
        Uri.parse('https://llm.example/chat/completions'),
        '',
        'test-model',
      );

  final List<String> calls;

  static const _domains = {
    'get_capability_status': 'device',
    'get_system_info': 'device',
    'get_access_points': 'wireless_discovery',
    'get_wireless_clients': 'wireless_discovery',
    'get_wifi_channels': 'wireless_discovery',
    'get_signal_history': 'wireless_monitoring',
    'get_wireless_events': 'wireless_monitoring',
    'list_captures': 'packet_analysis',
    'get_capture_metadata': 'packet_analysis',
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
          'serverInfo': {'name': 'Field Pi', 'version': '0.5'},
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
              'capabilities': [
                for (final entry in _domains.entries)
                  {
                    'name': entry.key,
                    'status': entry.value == 'device'
                        ? 'AVAILABLE'
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
    'shows reported capabilities and four real dashboard states (F4, F7–F8)',
    (tester) async {
      await _phoneLayout(tester);
      final calls = <String>[];
      await tester.pumpWidget(
        PiAgentApp(
          history: _EmptyHistory(),
          initialConnection: _DashboardConnection(calls),
        ),
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
      expect(find.text('get_access_points'), findsOneWidget);
      expect(find.text('未实现'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(_tab('Wireless'));
      await tester.pumpAndSettle();
      expect(
        find.text('Wireless monitoring is not available yet.'),
        findsOneWidget,
      );
      expect(find.text('已连接'), findsOneWidget);

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
      expect(calls, [
        'get_capability_status',
        'get_system_info',
        'get_system_info',
      ]);
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
