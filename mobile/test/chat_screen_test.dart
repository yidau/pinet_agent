import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piagent/agent/agent.dart';
import 'package:piagent/main.dart';
import 'package:piagent/storage/history.dart';

class _EmptyHistory extends History {
  @override
  Future<List<ChatEntry>> load() async => [];
}

void main() {
  testWidgets('phone layout exposes the acceptance task and connection form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(PiAgentApp(history: _EmptyHistory()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('运行 C++17 验收'));
    final composer = tester.widget<TextField>(find.byType(TextField));
    expect(composer.controller?.text, acceptancePrompt);

    await tester.tap(find.text('配置连接'));
    await tester.pumpAndSettle();
    expect(find.text('树莓派 MCP 地址'), findsOneWidget);
    expect(find.text('使用此连接'), findsOneWidget);
    expect(find.text('测试树莓派连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
