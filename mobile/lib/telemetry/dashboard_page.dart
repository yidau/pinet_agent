import 'package:fixnum/fixnum.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';
import 'monitor_radar.dart';
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: connection,
    builder: (context, _) => _dashboard(context),
  );

  Widget _dashboard(BuildContext context) {
    final snapshot = connection.snapshot;
    final phase = connection.phase;
    final online = phase == TelemetryPhase.live && !connection.stale;
    final radar = switch (phase) {
      TelemetryPhase.denied || TelemetryPhase.incompatible => RadarState.locked,
      TelemetryPhase.connecting ||
      TelemetryPhase.retrying => RadarState.connecting,
      TelemetryPhase.stopped => RadarState.offline,
      TelemetryPhase.live when !online => RadarState.stale,
      TelemetryPhase.live when snapshot?.capture.datasourceState == 'ready' =>
        RadarState.capturing,
      _ => RadarState.degraded,
    };
    final color = online
        ? ConsoleColors.successOf(context)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      key: const PageStorageKey('telemetry-dashboard'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        ConsoleCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              MonitorRadar(
                state: radar,
                revision: connection.snapshotRevision.value,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.occupied
                          ? '另一会话占用'
                          : radar == RadarState.stale
                          ? '快照已过期'
                          : radar == RadarState.degraded
                          ? '设备在线，监听受限'
                          : _phaseLabel(phase),
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(color: color),
                    ),
                    if (connection.snapshotAge case final age?)
                      Text(
                        '${age.inSeconds} 秒前收到快照',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (snapshot?.hasObservationSession() == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        snapshot!.observationSession.active
                            ? '连续有效观测 · ${_observationTime(snapshot.observationSession.continuousActiveMs)}'
                            : '等待有效采集',
                      ),
                    ],
                    if (!online && connection.isConfigured)
                      TextButton(
                        onPressed: connection.reconnect,
                        child: const Text('重新连接'),
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
          if (!connection.supportsV2)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('升级树莓派端后可使用档位切换和高危确认。'),
            ),
          if (snapshot.hasDeviceHealth()) ...[
            const SizedBox(height: 16),
            _HealthOverview(
              snapshot: snapshot,
              connection: connection,
              online: online,
            ),
          ],
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

String _observationTime(Int64 value) {
  final duration = Duration(milliseconds: value.toInt());
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(duration.inHours)}:${two(duration.inMinutes % 60)}:${two(duration.inSeconds % 60)}';
}

class _HealthOverview extends StatelessWidget {
  const _HealthOverview({
    required this.snapshot,
    required this.connection,
    required this.online,
  });
  final MonitoringSnapshot snapshot;
  final TelemetryConnection connection;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final delivery = snapshot.highRiskDelivery;
    final pressure = snapshot.resourcePressure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsoleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (pressure.level) {
                ResourceLevel.NORMAL => '设备资源正常',
                ResourceLevel.LEVEL1_WARN => '一级资源压力 · 提醒',
                ResourceLevel.LEVEL2_FALLBACK => '二级资源压力 · 回退轻量',
                _ => '资源压力未报告',
              }, style: Theme.of(context).textTheme.titleMedium),
              if (pressure.reason.isNotEmpty) Text(pressure.reason),
              if (snapshot.hasHighRiskDelivery()) ...[
                const SizedBox(height: 8),
                Text(
                  delivery.storageAvailable
                      ? '高危投递 · ${delivery.pendingCount} 待确认 · ${delivery.ackedCount} 已确认'
                      : '高危投递 · 存储不可用',
                ),
                if (delivery.expiredCount > Int64.ZERO ||
                    delivery.overflowEvictedCount > Int64.ZERO ||
                    delivery.overflowRejectedCount > Int64.ZERO ||
                    delivery.storageErrorCount > Int64.ZERO ||
                    delivery.previousBootDiscardedCount > Int64.ZERO)
                  Text(
                    '交付存在缺口 · 过期 ${delivery.expiredCount} · 队列淘汰 ${delivery.overflowEvictedCount}'
                    ' · 拒绝 ${delivery.overflowRejectedCount} · 存储错误 ${delivery.storageErrorCount}'
                    ' · 上次开机 ${delivery.previousBootDiscardedCount}',
                  ),
              ],
            ],
          ),
        ),
        for (final component in snapshot.deviceHealth.components) ...[
          const SizedBox(height: 8),
          ConsoleCard(
            child: ListTile(
              leading: Icon(switch (component.componentId) {
                ComponentId.BLE => Icons.bluetooth,
                ComponentId.MGMT_WIFI => Icons.router_outlined,
                ComponentId.ALERT_INPUT => Icons.shield_outlined,
                _ => Icons.wifi_tethering,
              }),
              title: Text(_componentName(component.componentId)),
              subtitle: Text(
                '${_componentState(component.state)}'
                '${component.recoveryPhase.isEmpty ? '' : ' · ${_recoveryState(component.recoveryPhase)}'}'
                '${component.reason.isEmpty ? '' : ' · ${component.reason}'}',
              ),
              trailing: component.componentId == ComponentId.ALERT_INPUT
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: component.componentId == ComponentId.ALERT_INPUT
                  ? null
                  : () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => _RecoveryPanel(
                        connection: connection,
                        id: component.componentId,
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

String _componentName(ComponentId value) => switch (value) {
  ComponentId.MGMT_WIFI => '管理热点',
  ComponentId.MONITOR_WIFI => '外接监听网卡',
  ComponentId.BLE => '蓝牙',
  ComponentId.ALERT_INPUT => '告警接入',
  _ => '设备组件',
};

String _componentState(ComponentState value) => switch (value) {
  ComponentState.READY => '就绪',
  ComponentState.IDLE => '空闲就绪',
  ComponentState.STARTING => '正在启动',
  ComponentState.DEGRADED => '功能受限',
  ComponentState.FAILED => '失败',
  _ => '未知',
};

String _recoveryState(String value) => switch (value) {
  'checking' => '检查中',
  'recovering' => '恢复中',
  'verifying' => '等待设备确认',
  'ready' => '已确认',
  'failed' => '未恢复',
  _ => value,
};

class _RecoveryPanel extends StatefulWidget {
  const _RecoveryPanel({required this.connection, required this.id});
  final TelemetryConnection connection;
  final ComponentId id;

  @override
  State<_RecoveryPanel> createState() => _RecoveryPanelState();
}

class _RecoveryPanelState extends State<_RecoveryPanel> {
  bool _allowRestart = false;
  bool _busy = false;
  String? _result;

  Future<void> _recover() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final response = await widget.connection.recover(
        widget.id,
        allowHotspotRestart: _allowRestart,
      );
      _result = response.accepted ? '设备已接收请求，等待状态回读。' : response.reason;
    } catch (_) {
      _result = '无法发送恢复请求，请检查连接。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.connection,
    builder: (context, _) {
      final health = widget.connection.snapshot?.deviceHealth.components
          .where((entry) => entry.componentId == widget.id)
          .firstOrNull;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConsoleHeading(_componentName(widget.id)),
              if (health != null)
                Text(
                  '${_componentState(health.state)} · ${_recoveryState(health.recoveryPhase)} ${health.reason}',
                ),
              if (widget.id == ComponentId.MGMT_WIFI)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('必要时允许重启热点'),
                  subtitle: const Text('重启会短暂断开手机连接。'),
                  value: _allowRestart,
                  onChanged: (value) =>
                      setState(() => _allowRestart = value ?? false),
                ),
              if (_result case final result?) Text(result),
              const SizedBox(height: 8),
              FilledButton(
                onPressed:
                    _busy ||
                        widget.connection.stale ||
                        !widget.connection.supportsV2
                    ? null
                    : _recover,
                child: const Text('检查并恢复'),
              ),
            ],
          ),
        ),
      );
    },
  );
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
