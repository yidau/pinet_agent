import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:piagent/storage/history.dart';
import 'package:piagent/ui/investigation_workspace.dart';

void main() {
  testWidgets('investigation links a result to its recorded tool evidence', (
    tester,
  ) async {
    final draft = TextEditingController();
    addTearDown(draft.dispose);
    const entries = [
      ChatEntry('user', '查看附近接入点'),
      ChatEntry(
        'tool',
        'get_access_points · 完成',
        details: '{"source":"managed_scan","timestamp":"2026-01-03T01:02:03Z","total":2}',
      ),
      ChatEntry('error', 'get_signal_history · 失败', details: '信号历史不可用'),
      ChatEntry('assistant', '设备报告了两个接入点。'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InvestigationWorkspace(
            entries: entries,
            draft: draft,
            activeTool: null,
            busy: false,
            loading: false,
            historyWarning: false,
            connected: true,
            onSend: () {},
          ),
        ),
      ),
    );
    expect(find.text('设备报告了两个接入点。'), findsOneWidget);
    expect(find.textContaining('1 项完成 · 1 项失败'), findsOneWidget);
    expect(find.textContaining('2026-01-03'), findsNothing);
    await tester.tap(find.text('调查记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取接入点列表'));
    await tester.pumpAndSettle();
    expect(find.text('数据来源 · managed_scan'), findsOneWidget);
    expect(find.text('设备返回时间 · 2026-01-03T01:02:03Z'), findsOneWidget);
    expect(latestEvidenceFinding(entries), entries.last.text);
    expect(
      latestEvidenceFinding([
        const ChatEntry('user', '查看可能的风险'),
        const ChatEntry('tool', '查询'),
        const ChatEntry('error', 'get_kismet_alerts · 失败', details: '未知'),
        const ChatEntry('assistant', '结果未知。'),
      ]),
      isNull,
    );
  });
}
