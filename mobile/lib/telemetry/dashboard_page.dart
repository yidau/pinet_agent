import 'package:fixnum/fixnum.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';
import 'monitoring_widgets.dart';
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

  bool get _online =>
      connection.phase == TelemetryPhase.live && !connection.stale;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: connection,
    builder: (context, _) {
      final snapshot = connection.snapshot;
      return ListView(
        key: const PageStorageKey('telemetry-dashboard'),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        children: [
          ConsoleHeading(
            '仪表盘',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_online && connection.isConfigured)
                  IconButton(
                    tooltip: '重新连接',
                    onPressed: connection.reconnect,
                    icon: const Icon(Icons.refresh),
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
          if (snapshot == null)
            Text(connection.isConfigured ? '等待遥测连接。' : '扫码注册树莓派后，将自动接收遥测数据。')
          else ...[
            _wireless(context, snapshot),
            const SizedBox(height: 10),
            _system(context, snapshot),
            const SizedBox(height: 12),
            _components(context, snapshot),
          ],
        ],
      );
    },
  );

  void _details(
    BuildContext context,
    String title,
    List<Widget> Function(MonitoringSnapshot) content,
  ) {
    showMonitoringSheet(
      context,
      (_) => ListenableBuilder(
        listenable: connection,
        builder: (context, _) {
          final snapshot = connection.snapshot;
          return MonitoringSheetBody(
            title,
            children: [
              if (!_online) const Text('当前显示上次快照'),
              if (snapshot != null) ...content(snapshot),
            ],
          );
        },
      ),
    );
  }

  Widget _wireless(BuildContext context, MonitoringSnapshot snapshot) {
    final wireless = snapshot.wireless;
    final capture = snapshot.capture;
    final status = !_online
        ? MonitorStatus.unknown
        : capture.datasourceError
        ? MonitorStatus.failed
        : wireless.coverage == 'live_source_window' &&
              _fresh(snapshot.timestampMs, wireless.sampledAtMs)
        ? MonitorStatus.normal
        : MonitorStatus.limited;
    final summary = connection.occupied
        ? '另一会话占用'
        : !_online
        ? (connection.stale && connection.phase == TelemetryPhase.live
              ? '快照已过期'
              : '遥测待连接')
        : capture.coverage != 'live_monitor_active'
        ? '设备在线，监听受限'
        : status == MonitorStatus.normal
        ? '监听中 · ${captureProfileLabel(snapshot.capturePolicy.actual)}'
        : '监听中 · 部分观测';
    final packets = capture.hasPacketsPerSecond()
        ? capture.packetsPerSecond
        : capture.hasProcessedPacketsPerSecond()
        ? capture.processedPacketsPerSecond
        : null;
    return _SummaryCard(
      title: '无线观测',
      icon: Icons.sensors,
      status: status,
      subtitle: summary,
      time: wireless.hasSampledAtMs()
          ? formatTelemetryTime(wireless.sampledAtMs, includeDate: false)
          : null,
      onTap: () => _details(context, '无线观测', _wirelessDetails),
      readings: [
        ('AP', wireless.hasApCount() ? '${wireless.apCount}' : null, status),
        (
          '客户端',
          wireless.hasClientCount() ? '${wireless.clientCount}' : null,
          status,
        ),
        ('数据包/秒', packets?.toString(), status),
      ],
    );
  }

  Widget _system(BuildContext context, MonitoringSnapshot snapshot) {
    final system = snapshot.system;
    final pressure = snapshot.resourcePressure;
    final fresh = _online && _fresh(snapshot.timestampMs, system.sampledAtMs);
    final availability = fresh ? MonitorStatus.normal : MonitorStatus.unknown;
    final status = !fresh
        ? MonitorStatus.unknown
        : switch (pressure.level) {
            ResourceLevel.NORMAL => MonitorStatus.normal,
            ResourceLevel.LEVEL1_WARN => MonitorStatus.limited,
            ResourceLevel.LEVEL2_FALLBACK => MonitorStatus.failed,
            _ => MonitorStatus.unknown,
          };
    return _SummaryCard(
      title: '系统资源',
      status: status,
      onTap: () => _details(context, '系统资源', _systemDetails),
      readings: [
        (
          'CPU',
          system.hasCpuUsage() ? _number(system.cpuUsage, '%') : null,
          pressure.reason.startsWith('cpu_') ? status : availability,
        ),
        (
          '可用内存',
          system.hasMemoryAvailableBytes()
              ? _memory(system.memoryAvailableBytes)
              : null,
          pressure.reason.startsWith('available_memory') ||
                  pressure.reason.startsWith('memory_psi')
              ? status
              : availability,
        ),
        (
          '温度',
          system.hasTemperatureC() ? _number(system.temperatureC, ' °C') : null,
          !fresh || !system.hasTemperatureC()
              ? MonitorStatus.unknown
              : switch (system.temperatureC) {
                  >= 85 => MonitorStatus.failed,
                  >= 80 => MonitorStatus.limited,
                  _ => MonitorStatus.normal,
                },
        ),
      ],
    );
  }

  Widget _components(BuildContext context, MonitoringSnapshot snapshot) {
    final health = {
      for (final entry in snapshot.deviceHealth.components)
        entry.componentId: entry,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设备状态', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final twoColumns =
                constraints.maxWidth >=
                MediaQuery.textScalerOf(context).scale(280);
            final width = twoColumns
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final id in _componentNames.keys)
                  SizedBox(
                    width: width,
                    child: ConsoleCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        visualDensity: VisualDensity.compact,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 9,
                        ),
                        horizontalTitleGap: 7,
                        minLeadingWidth: 18,
                        leading: _componentStatus(
                          health[id],
                          _online,
                        ).indicator(context),
                        title: Text(
                          _componentNames[id]!,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 16),
                        onTap: () => showMonitoringSheet(
                          context,
                          (_) =>
                              _ComponentPanel(connection: connection, id: id),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final status in MonitorStatus.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(child: status.indicator(context, size: 13)),
                  const SizedBox(width: 3),
                  Text(
                    status.label,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

const _componentNames = {
  ComponentId.ALERT_INPUT: '告警接入',
  ComponentId.MGMT_WIFI: '管理热点',
  ComponentId.MONITOR_WIFI: '外接监听网卡',
  ComponentId.BLE: '蓝牙',
};

MonitorStatus _componentStatus(ComponentHealth? health, bool online) {
  if (!online || health == null) return MonitorStatus.unknown;
  if (health.componentId == ComponentId.ALERT_INPUT) {
    if (health.reason == 'polling_best_effort') return MonitorStatus.normal;
    if (health.reason == 'alert_input_unavailable') return MonitorStatus.failed;
  }
  return switch (health.state) {
    ComponentState.READY || ComponentState.IDLE => MonitorStatus.normal,
    ComponentState.DEGRADED => MonitorStatus.limited,
    ComponentState.FAILED => MonitorStatus.failed,
    _ => MonitorStatus.unknown,
  };
}

class _ComponentPanel extends StatefulWidget {
  const _ComponentPanel({required this.connection, required this.id});
  final TelemetryConnection connection;
  final ComponentId id;

  @override
  State<_ComponentPanel> createState() => _ComponentPanelState();
}

class _ComponentPanelState extends State<_ComponentPanel> {
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
      final snapshot = widget.connection.snapshot;
      final health = snapshot?.deviceHealth.components
          .where((entry) => entry.componentId == widget.id)
          .firstOrNull;
      final online =
          widget.connection.phase == TelemetryPhase.live &&
          !widget.connection.stale;
      final status = _componentStatus(health, online);
      final alert = widget.id == ComponentId.ALERT_INPUT;
      final reason = switch (health?.reason) {
        'polling_best_effort' => '可读取 Kismet 告警，约每 3 秒查询一次。缓存有限，查询中断时可能漏读。',
        'alert_input_unavailable' => '当前无法读取 Kismet 告警。',
        'highrisk_pending_durable_commit' => '有高危告警正在等待写入本地存储。',
        final String reason => reason,
        _ => '',
      };
      return MonitoringSheetBody(
        _componentNames[widget.id]!,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: status.indicator(context),
            title: Text(status.label),
            subtitle: reason.isNotEmpty ? Text(reason) : null,
          ),
          if (health?.hasSampledAtMs() == true)
            _detail('最近检查', formatTelemetryTime(health!.sampledAtMs)),
          if (health?.hasLastOkMs() == true)
            _detail('上次正常', formatTelemetryTime(health!.lastOkMs)),
          if (health != null && health.recoveryPhase.isNotEmpty)
            _detail('恢复进度', switch (health.recoveryPhase) {
              'checking' => '检查中',
              'recovering' => '恢复中',
              'verifying' => '等待设备确认',
              'ready' => '已确认',
              'failed' => '未恢复',
              _ => health.recoveryPhase,
            }),
          if (alert && snapshot?.hasHighRiskDelivery() == true)
            ..._deliveryDetails(snapshot!.highRiskDelivery),
          if (!alert) ...[
            if (widget.id == ComponentId.MGMT_WIFI)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('必要时允许重启热点'),
                subtitle: const Text('重启会短暂断开手机连接。'),
                value: _allowRestart,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _allowRestart = value ?? false),
              ),
            if (_result case final result?) Text(result),
            FilledButton(
              onPressed: _busy || !online || !widget.connection.supportsV2
                  ? null
                  : _recover,
              child: const Text('检查并恢复'),
            ),
          ],
        ],
      );
    },
  );
}

List<Widget> _deliveryDetails(HighRiskDeliveryStatus delivery) => [
  const Divider(),
  _detail(
    '高危投递',
    delivery.storageAvailable
        ? '${delivery.pendingCount} 待确认 · ${delivery.ackedCount} 已确认'
        : '存储不可用',
  ),
  if (delivery.expiredCount > Int64.ZERO ||
      delivery.overflowEvictedCount > Int64.ZERO ||
      delivery.overflowRejectedCount > Int64.ZERO ||
      delivery.storageErrorCount > Int64.ZERO ||
      delivery.previousBootDiscardedCount > Int64.ZERO)
    _detail(
      '交付缺口',
      '过期 ${delivery.expiredCount} · 淘汰 ${delivery.overflowEvictedCount} · 拒绝 ${delivery.overflowRejectedCount} · 存储错误 ${delivery.storageErrorCount} · 上次开机 ${delivery.previousBootDiscardedCount}',
    ),
];

String formatTelemetryTime(Int64 timestampMs, {bool includeDate = true}) {
  final milliseconds = timestampMs.toInt();
  if (milliseconds <= 0 || milliseconds > 8640000000000000) return '时间未报告';
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String pair(int value) => value.toString().padLeft(2, '0');
  final clock = '${pair(time.hour)}:${pair(time.minute)}:${pair(time.second)}';
  return includeDate ? '${pair(time.month)}-${pair(time.day)}  $clock' : clock;
}

bool _fresh(Int64 snapshotMs, Int64 sampleMs) =>
    sampleMs > Int64.ZERO && (snapshotMs - sampleMs).abs() <= Int64(20000);

String _number(num? value, String unit, {int precision = 1}) =>
    value != null && value.isFinite
    ? '${value.toStringAsFixed(precision)}$unit'
    : '未报告';

String _memory(Int64 bytes) {
  final mib = bytes.toDouble() / (1024 * 1024);
  return mib >= 1024
      ? _number(mib / 1024, ' GiB')
      : _number(mib, ' MiB', precision: 0);
}

Widget _detail(String label, String value) => ListTile(
  contentPadding: EdgeInsets.zero,
  visualDensity: VisualDensity.compact,
  title: Text(label),
  subtitle: Text(value),
);

List<Widget> _systemDetails(MonitoringSnapshot snapshot) {
  final system = snapshot.system;
  final pressure = snapshot.resourcePressure;
  return [
    _detail('设备资源', switch (pressure.level) {
      ResourceLevel.NORMAL => '正常',
      ResourceLevel.LEVEL1_WARN => '一级资源压力',
      ResourceLevel.LEVEL2_FALLBACK => '二级资源压力 · 回退轻量',
      _ => '未报告',
    }),
    if (pressure.reason.isNotEmpty)
      _detail('压力原因', switch (pressure.reason) {
        'cpu_utilization' || 'cpu_utilization_critical' => 'CPU 使用率持续偏高',
        'available_memory' || 'available_memory_critical' => '可用内存偏低',
        'memory_psi' || 'memory_psi_critical' => '内存压力持续偏高',
        _ => pressure.reason,
      }),
    if (system.hasTemperatureC())
      _detail(
        'CPU 温度',
        [
          _number(system.temperatureC, ' °C'),
          if (system.temperatureC >= 85)
            '已达树莓派限温'
          else if (system.temperatureC >= 80)
            '进入降频温区',
        ].join(' · '),
      ),
    _detail(
      'CPU 压力 PSI',
      _number(system.hasCpuPsiSomeAvg10() ? system.cpuPsiSomeAvg10 : null, '%'),
    ),
    _detail(
      '内存压力 PSI',
      _number(
        system.hasMemoryPsiSomeAvg10() ? system.memoryPsiSomeAvg10 : null,
        '%',
      ),
    ),
    _detail(
      'I/O 压力 PSI',
      _number(
        system.ioPressure.hasSomeAvg10() ? system.ioPressure.someAvg10 : null,
        '%',
      ),
    ),
    if (system.hasSampledAtMs())
      _detail('采样时间', formatTelemetryTime(system.sampledAtMs)),
  ];
}

List<Widget> _wirelessDetails(MonitoringSnapshot snapshot) {
  final capture = snapshot.capture;
  final wireless = snapshot.wireless;
  final observation = snapshot.observationSession;
  final duration = Duration(
    milliseconds: observation.continuousActiveMs.toInt(),
  );
  return [
    _detail(
      'Kismet',
      capture.hasKismetRunning()
          ? (capture.kismetRunning ? '运行中' : '已停止')
          : '未报告',
    ),
    _detail('覆盖', switch (wireless.coverage) {
      'live_source_window' => '监听网卡 · 实时观测',
      'partial_live_source_window' => '监听网卡 · 部分观测',
      'source_view_unavailable' => '监听已就绪，设备视图暂不可读',
      'resource_fallback' => '资源回退，暂停设备详情',
      _ => '待确认采集状态',
    }),
    if (capture.reason.isNotEmpty) _detail('设备原因', capture.reason),
    if (observation.active)
      _detail(
        '连续观测',
        '${duration.inHours} 小时 ${duration.inMinutes % 60} 分 ${duration.inSeconds % 60} 秒',
      ),
    if (capture.currentChannel.isNotEmpty)
      _detail('当前信道', capture.currentChannel),
    if (capture.hasDroppedPackets())
      _detail('丢弃数据包', '${capture.droppedPackets}'),
    if (wireless.hasSampledAtMs())
      _detail('采样时间', formatTelemetryTime(wireless.sampledAtMs)),
  ];
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.status,
    required this.onTap,
    required this.readings,
    this.subtitle,
    this.time,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? time;
  final IconData? icon;
  final MonitorStatus status;
  final VoidCallback onTap;
  final List<(String, String?, MonitorStatus)> readings;

  @override
  Widget build(BuildContext context) => ConsoleCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                if (icon case final shown?) ...[
                  Icon(shown, size: 24, color: status.color(context)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle case final shown?)
                        Text(
                          shown,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: status.color(context)),
                        ),
                    ],
                  ),
                ),
                if (time case final shown?)
                  Flexible(
                    child: Text(
                      '采样 $shown',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  status.indicator(context, size: 15),
                const Icon(Icons.chevron_right, size: 16),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Divider(),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, value, state) in readings)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            (value == null || value == '未报告'
                                    ? MonitorStatus.unknown
                                    : state)
                                .indicator(context, size: 13),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          value ?? '未报告',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
