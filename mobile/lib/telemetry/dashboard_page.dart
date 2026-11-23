import 'package:fixnum/fixnum.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';
import 'proto/monitoring.pb.dart';
import 'telemetry_connection.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.connection,
    required this.onOpenMessages,
  });

  final TelemetryConnection connection;
  final VoidCallback onOpenMessages;

  @override
  Widget build(BuildContext context) {
    final snapshot = connection.snapshot;
    final phase = connection.phase;
    final online = phase == TelemetryPhase.live;
    final color = online
        ? ConsoleColors.successOf(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      key: const PageStorageKey('telemetry-dashboard'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        ConsoleCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.sensors, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _phaseLabel(phase),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (snapshot != null && snapshot.hasTimestampMs())
                      Text(
                        '${online ? '设备采样' : '最近一次快照'} · '
                        '${formatTelemetryTime(snapshot.timestampMs)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: connection.unreadCount == 0
                    ? '消息中心'
                    : '消息中心，${connection.unreadCount} 条未读',
                onPressed: onOpenMessages,
                icon: Badge(
                  isLabelVisible: connection.unreadCount > 0,
                  label: Text('${connection.unreadCount}'),
                  child: const Icon(Icons.notifications_outlined),
                ),
              ),
            ],
          ),
        ),
        if (snapshot == null) ...[
          const SizedBox(height: 12),
          Text(
            connection.isConfigured
                ? '收到设备快照后显示系统资源和无线观测。'
                : '扫码注册树莓派后，将自动接收遥测数据。',
          ),
        ] else ...[
          const SizedBox(height: 18),
          const ConsoleHeading('系统资源'),
          const SizedBox(height: 8),
          _SystemMetrics(
            snapshot.system,
            stale:
                !online ||
                _stale(snapshot.timestampMs, snapshot.system.sampledAtMs),
          ),
          const SizedBox(height: 18),
          const ConsoleHeading('无线观测'),
          const SizedBox(height: 8),
          _WirelessMetrics(snapshot, online: online),
        ],
      ],
    );
  }
}

String _phaseLabel(TelemetryPhase phase) => switch (phase) {
  TelemetryPhase.stopped => '遥测未连接',
  TelemetryPhase.connecting => '正在连接遥测',
  TelemetryPhase.live => '实时遥测',
  TelemetryPhase.retrying => '遥测已中断，正在重连',
  TelemetryPhase.denied => '设备未授权，请核对手机注册状态',
  TelemetryPhase.incompatible => '设备遥测版本不兼容',
};

String formatTelemetryTime(Int64 timestampMs) {
  final milliseconds = timestampMs.toInt();
  if (milliseconds <= 0 || milliseconds > 8640000000000000) return '时间未报告';
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String pair(int value) => value.toString().padLeft(2, '0');
  return '${pair(time.month)}-${pair(time.day)}  '
      '${pair(time.hour)}:${pair(time.minute)}:${pair(time.second)}';
}

bool _stale(Int64 snapshotMs, Int64 sampleMs) =>
    sampleMs <= Int64.ZERO || (snapshotMs - sampleMs).abs() > Int64(20000);

String _number(num? value, String unit, {int precision = 1}) =>
    value != null && value.isFinite
    ? '${value.toStringAsFixed(precision)}$unit'
    : '未报告';

class _SystemMetrics extends StatelessWidget {
  const _SystemMetrics(this.metrics, {required this.stale});
  final SystemMetrics metrics;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    const mib = 1024 * 1024;
    final memory = metrics.hasMemoryAvailableBytes()
        ? metrics.memoryAvailableBytes.toDouble() / mib
        : null;
    return ConsoleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stale)
            Text(
              '未收到近期系统采样',
              style: TextStyle(color: ConsoleColors.warningOf(context)),
            ),
          _Metrics(
            metrics: [
              (
                'CPU 使用率',
                _number(metrics.hasCpuUsage() ? metrics.cpuUsage : null, '%'),
              ),
              ('可用内存', _number(memory, ' MiB', precision: 0)),
              (
                'CPU 温度',
                _number(
                  metrics.hasTemperatureC() ? metrics.temperatureC : null,
                  ' °C',
                ),
              ),
              (
                'CPU 压力 PSI',
                _number(
                  metrics.hasCpuPsiSomeAvg10() ? metrics.cpuPsiSomeAvg10 : null,
                  '%',
                ),
              ),
              (
                '内存压力 PSI',
                _number(
                  metrics.hasMemoryPsiSomeAvg10()
                      ? metrics.memoryPsiSomeAvg10
                      : null,
                  '%',
                ),
              ),
              (
                'I/O 压力 PSI',
                _number(
                  metrics.ioPressure.hasSomeAvg10()
                      ? metrics.ioPressure.someAvg10
                      : null,
                  '%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WirelessMetrics extends StatelessWidget {
  const _WirelessMetrics(this.snapshot, {required this.online});
  final MonitoringSnapshot snapshot;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final capture = snapshot.capture;
    final wireless = snapshot.wireless;
    final source = capture.datasourceState.trim();
    final reason = capture.reason.trim();
    final coverage = switch (wireless.coverage.trim().toLowerCase()) {
      'live_source_window' => 'Monitor Mode 实时观测窗口',
      'partial_live_source_window' => 'Monitor Mode 部分观测',
      'source_view_unavailable' => '监听已就绪，设备视图暂不可读',
      'degraded' => '观测受限',
      'unavailable' || 'none' => '暂无有效数据源',
      _ =>
        capture.coverage == 'live_monitor_active'
            ? 'Monitor Mode'
            : capture.coverage == 'unavailable'
            ? '暂无有效数据源'
            : '',
    };
    final stale = !online || _stale(snapshot.timestampMs, wireless.sampledAtMs);
    final running = capture.hasKismetRunning()
        ? (capture.kismetRunning ? '运行中' : '已停止')
        : '未报告';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsoleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kismet · $running',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('监听网卡 · ${_sourceLabel(source)}'),
              if (coverage.isNotEmpty) Text('覆盖 · $coverage'),
              if (reason.isNotEmpty)
                Text(reason, style: Theme.of(context).textTheme.bodySmall),
              if (stale || wireless.truncated)
                Text(
                  stale ? '未收到近期无线采样' : '设备报告本次观测范围受限',
                  style: TextStyle(color: ConsoleColors.warningOf(context)),
                ),
              const SizedBox(height: 10),
              _Metrics(
                metrics: [
                  (
                    '已观测 AP',
                    wireless.hasApCount() ? '${wireless.apCount}' : '未报告',
                  ),
                  (
                    '已观测客户端',
                    wireless.hasClientCount()
                        ? '${wireless.clientCount}'
                        : '未报告',
                  ),
                ],
              ),
            ],
          ),
        ),
        if (wireless.priorityAps.isNotEmpty) ...[
          const SizedBox(height: 16),
          const ConsoleHeading('重点接入点'),
          const SizedBox(height: 8),
          for (final ap in wireless.priorityAps.take(8)) ...[
            ConsoleCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.wifi, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ap.ssid.isEmpty ? '隐藏网络' : ap.ssid,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          [
                            ap.bssid,
                            if (ap.channel.isNotEmpty) '信道 ${ap.channel}',
                            ap.security,
                          ].where((part) => part.isNotEmpty).join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _number(
                      ap.hasRssiDbm() ? ap.rssiDbm : null,
                      ' dBm',
                      precision: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ],
    );
  }
}

String _sourceLabel(String value) => switch (value.toLowerCase()) {
  'running' || 'available' || 'ready' => '运行中',
  'starting' => '正在启动',
  'degraded' => '受限',
  'unavailable' || 'absent' || 'missing' || 'unconfigured' => '不可用',
  'paused' => '已暂停',
  'stopped' => '已停止',
  'error' => '异常',
  _ => value.isEmpty ? '未报告' : value,
};

class _Metrics extends StatelessWidget {
  const _Metrics({required this.metrics});
  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (constraints.maxWidth / (126 * scale)).floor().clamp(
        1,
        3,
      );
      const spacing = 10.0;
      final width = (constraints.maxWidth - (columns - 1) * spacing) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final (label, value) in metrics)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(value, style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
            ),
        ],
      );
    },
  );
}
