import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piagent/agent/agent.dart';
import 'package:piagent/main.dart';
import 'package:piagent/storage/history.dart';

class _EmptyHistory extends History {
  @override
  Future<List<ChatEntry>> load() async => [];

  @override
  Future<void> add(ChatEntry entry) async {}
}

void main() {
  testWidgets('phone shows device controls and an offline query result', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(PiAgentApp(history: _EmptyHistory()));
    await tester.pumpAndSettle();

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('运行 C++17 验收'), findsNothing);
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
