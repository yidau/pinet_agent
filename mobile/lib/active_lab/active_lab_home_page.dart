import 'package:material_ui/material_ui.dart';

import '../telemetry/telemetry_connection.dart';

/// Entry point for laboratory-only radio tests.
class ActiveLabHomePage extends StatelessWidget {
  const ActiveLabHomePage({super.key, required this.connection, required this.onOpenMonitoring});

  final TelemetryConnection connection;
  final VoidCallback onOpenMonitoring;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: connection,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ACTIVE RADIO LAB', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text('单张 USB 监听网卡与 Kismet 分时使用，仅对预登记的射频隔离实验 AP 开放。'),
            const SizedBox(height: 10),
            Text(connection.supportsRadioLab
                ? '实验协议已连接。请从探测结果选择授权 AP。'
                : '等待支持无线实验的树莓派版本或实时连接。'),
          ]),
        )),
        const ListTile(
          leading: Icon(Icons.radar),
          title: Text('探测与目标选择'),
          subtitle: Text('复用 Kismet 观测到的 SSID、BSSID 和信道。'),
        ),
        const ListTile(
          leading: Icon(Icons.verified_user_outlined),
          title: Text('授权与模式交接'),
          subtitle: Text('必须匹配设备所有者配置的 RF 隔离实验 AP。'),
        ),
        const ListTile(
          leading: Icon(Icons.play_circle_outline),
          title: Text('持续实验与手动结束'),
          subtitle: Text('20 秒租约持续续期，硬性最长 10 分钟。'),
        ),
        const ListTile(
          leading: Icon(Icons.settings_backup_restore),
          title: Text('恢复监听与结果'),
          subtitle: Text('实验结束后自动恢复 Kismet，展示实际证据范围。'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onOpenMonitoring,
          icon: const Icon(Icons.radar),
          label: const Text('前往探测模式选择 AP'),
        ),
        const SizedBox(height: 12),
        const Text('公共网络仅被动监控；不会对未经授权的 AP 发射。'
            'Deauth、洪泛、干扰型连续测试均未开放。'),
      ],
    ),
  );
}
