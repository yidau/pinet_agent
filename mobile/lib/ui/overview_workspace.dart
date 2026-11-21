import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../mcp/tool_registry.dart';
import '../network.dart';
import 'console_style.dart';
import 'wifi_networks.dart';
import 'workspace_data.dart';

class OverviewWorkspace extends StatelessWidget {
  const OverviewWorkspace({
    super.key,
    required this.session,
    required this.observations,
    required this.aiFinding,
    required this.onOpenAi,
  });

  final DeviceSession? session;
  final Map<String, Json> observations;
  final String? aiFinding;
  final VoidCallback onOpenAi;

  @override
  Widget build(BuildContext context) {
    final data = WorkspaceData(session, observations);
    final colors = Theme.of(context).colorScheme;
    final alertTool = session?.registry['get_kismet_alerts'] != null
        ? 'get_kismet_alerts'
        : 'get_security_events';
    final alertField = alertTool == 'get_kismet_alerts' ? 'alerts' : 'events';
    final activities = _activities(data, alertTool, alertField);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _DeviceOverview(data: data),
        const SizedBox(height: 20),
        ConsoleHeading(
          '网络观测',
          trailing: TextButton.icon(
            onPressed: () => _showSources(context, data),
            icon: const Icon(Icons.layers_outlined, size: 16),
            label: const Text('数据来源'),
          ),
        ),
        const SizedBox(height: 8),
        _Metrics(data: data),
        if (data.result('get_access_points') case final Json points)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '接入点 · ${evidenceLine(points)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 20),
        ConsoleHeading(
          '最近活动',
          trailing: activities.length <= 4
              ? null
              : TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (_) => SafeArea(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                        children: [
                          const ConsoleHeading('最近活动'),
                          ...activities.map((item) => _ActivityTile(item)),
                        ],
                      ),
                    ),
                  ),
                  child: const Text('查看全部'),
                ),
        ),
        const SizedBox(height: 8),
        ConsoleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.count(alertTool, alertField) case final String count)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 17,
                        color: count == '0'
                            ? colors.onSurfaceVariant
                            : ConsoleColors.warningOf(context),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '已记录告警 · $count',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                    ],
                  ),
                ),
              if (activities.isEmpty)
                Text(
                  session == null
                      ? '连接设备后可查看网络事件和告警。'
                      : data.rows('get_wireless_events', 'events') == null &&
                            data.rows(alertTool, alertField) == null
                      ? data.reason('get_wireless_events')
                      : '当前记录中没有带时间的活动。',
                  style: _quiet(context),
                )
              else
                for (final item in activities.take(4)) _ActivityTile(item),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const ConsoleHeading('AI 发现'),
        const SizedBox(height: 8),
        ConsoleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 22,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      aiFinding == null ? '分析当前环境' : '最近一次调查',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                aiFinding ?? '让 AI 根据设备已记录的接入点、事件和告警，整理值得关注的变化。',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: _quiet(context),
              ),
              TextButton.icon(
                onPressed: onOpenAi,
                icon: const Icon(Icons.arrow_forward, size: 17),
                label: Text(aiFinding == null ? '打开 AI 分析' : '查看调查与证据'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

TextStyle? _quiet(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

class _DeviceOverview extends StatelessWidget {
  const _DeviceOverview({required this.data});
  final WorkspaceData data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final system = data.result('get_system_info');
    final cpu = data.result('get_cpu_info');
    final replay = data.result('get_capture_status');
    final kismet = data.session?.registry.kismet;
    final sources = data.rows('get_kismet_datasources', 'datasources');
    final live = sources
        ?.where(
          (s) =>
              (s['driver'] == 'linuxwifi' || s['driver'] == 'linuxbluetooth') &&
              s['running'] == true &&
              s['paused'] != true &&
              s['error'] != true,
        )
        .length;
    final platform = [
      ?displayText(system?['os']),
      ?displayText(system?['architecture']),
    ].join(' · ');
    return ConsoleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Icon(
                    Icons.memory_rounded,
                    size: 26,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayText(system?['hostname']) ?? 'Raspberry Pi',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      platform.isEmpty
                          ? data.reason('get_system_info')
                          : platform,
                      style: _quiet(context),
                    ),
                  ],
                ),
              ),
              if (data.session != null)
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '设备与网络详情',
                  onPressed: () => _deviceDetails(context, data),
                ),
            ],
          ),
          const Divider(height: 23),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _IconText(
                Icons.sensors,
                switch (kismet?.running) {
                  true => '观测引擎运行中',
                  false => '观测引擎已停止',
                  null => '引擎状态未报告',
                },
                color: kismet?.running == true
                    ? ConsoleColors.successOf(context)
                    : colors.onSurfaceVariant,
              ),
              if (live != null) _IconText(Icons.radar, '$live 个活动无线源'),
              if (cpu?['temperature_c'] case final num degrees
                  when degrees.isFinite)
                _IconText(
                  Icons.thermostat_outlined,
                  '${degrees.toStringAsFixed(1)} °C',
                ),
              if (replay?['state'] == 'running' ||
                  replay?['state'] == 'starting')
                const _IconText(Icons.replay, '文件重放进行中'),
            ],
          ),
          if (system != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                evidenceLine(system),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

void _deviceDetails(BuildContext context, WorkspaceData data) {
  final system = data.result('get_system_info');
  final net = data.result('get_network_profile');
  final cpu = data.result('get_cpu_info');
  final rows = [
    ('主机名', displayText(system?['hostname'])),
    ('操作系统', displayText(system?['os'])),
    ('内核', displayText(system?['kernel'])),
    ('架构', displayText(system?['architecture'])),
    if (cpu?['used_percent'] case final num n when n.isFinite)
      ('CPU 使用率', '${n.toStringAsFixed(1)}%'),
    ('SSID', displayText(net?['ssid'])),
    ('接口', displayText(net?['interface'])),
    ('IP 地址', displayText(net?['ip_address'])),
    ('网关', displayText(net?['gateway'])),
  ];
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          const ConsoleHeading('设备与网络详情'),
          for (final (label, value) in rows)
            if (value != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                subtitle: SelectableText(value),
              ),
          if (system != null)
            Text(evidenceLine(system))
          else
            Text(data.reason('get_system_info')),
          if (cpu != null) Text(evidenceLine(cpu)),
          if (net != null)
            Text(evidenceLine(net))
          else
            Text('网络信息 · ${data.reason('get_network_profile')}'),
        ],
      ),
    ),
  );
}

class _IconText extends StatelessWidget {
  const _IconText(this.icon, this.text, {this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 5),
      Flexible(
        child: Text(text, style: Theme.of(context).textTheme.labelMedium),
      ),
    ],
  );
}

const _metrics = [
  ('get_access_points', 'access_points', '接入点', Icons.wifi),
  ('get_wireless_clients', 'clients', '客户端', Icons.devices_outlined),
  ('get_wireless_events', 'events', '网络事件', Icons.timeline_outlined),
];

String? _apCount(WorkspaceData data) {
  final rows = data.rows('get_access_points', 'access_points');
  if (rows == null) return null;
  final count = rows.map(wifiBssid).whereType<String>().toSet().length;
  return data.result('get_access_points')?['truncated'] == true
      ? '≥$count'
      : '$count';
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.data});
  final WorkspaceData data;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scaled = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = (box.maxWidth / (85 * scaled + 8)).floor().clamp(1, 3);
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (tool, field, label, icon) in _metrics)
            SizedBox(
              width: (box.maxWidth - (columns - 1) * 8) / columns,
              child: Semantics(
                button: true,
                label: '查看$label的数据来源',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showSources(context, data),
                  child: ConsoleCard(
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (tool == 'get_access_points'
                                  ? _apCount(data)
                                  : data.count(tool, field)) ??
                              '—',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

void _showSources(BuildContext context, WorkspaceData data) {
  final kismet = data.session?.registry.kismet;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .76,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            const ConsoleHeading('观测数据来源'),
            for (final (tool, _, label, icon) in _metrics)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(label),
                subtitle: Text(switch (data.result(tool)) {
                  final Json reply => evidenceLine(reply),
                  _ => data.reason(tool),
                }),
              ),
            const Divider(),
            if (kismet != null)
              for (final entry in kismet.sources.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(sourceName(entry.key)),
                  leading: Icon(
                    entry.value.status == CapabilityStatus.available
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                  ),
                  subtitle: Text(switch (entry.value.status) {
                    CapabilityStatus.available => '可用',
                    _ => displayText(entry.value.reason) ?? '当前不可用',
                  }),
                ),
          ],
        ),
      ),
    ),
  );
}

typedef _Activity = ({
  String title,
  String detail,
  String source,
  DateTime time,
  IconData icon,
  bool alert,
});

List<_Activity> _activities(
  WorkspaceData data,
  String alertTool,
  String alertField,
) {
  final entries = <_Activity>[];
  final seen = <(DateTime, String, String)>{};
  for (final (tool, field, alert) in [
    (alertTool, alertField, true),
    ('get_wireless_events', 'events', false),
  ]) {
    for (final row in data.rows(tool, field) ?? const <Json>[]) {
      final time = deviceTime(row['timestamp']);
      final kind = displayText(row['type']) ?? '';
      final message = displayText(row['message'] ?? row['description']) ?? '';
      if (time == null ||
          (kind.isEmpty && message.isEmpty) ||
          !seen.add((time, kind, message))) {
        continue;
      }
      entries.add((
        title: kind.isEmpty ? (alert ? '设备告警' : '网络事件') : kind,
        detail: message,
        source: sourceName(row['source'] ?? data.result(tool)?['source']),
        time: time,
        icon: alert ? Icons.warning_amber_rounded : Icons.timeline,
        alert: alert,
      ));
    }
  }
  final aps = data.rows('get_access_points', 'access_points');
  if (aps != null) {
    final times = [
      for (final ap in aps)
        if (deviceTime(ap['observed_at']) case final DateTime time) time,
    ]..sort();
    if (times.isNotEmpty) {
      entries.add((
        title: '接入点观测',
        detail: '本次视图包含 ${_apCount(data)} 个接入点',
        source: sourceName(data.result('get_access_points')?['source']),
        time: times.last,
        icon: Icons.wifi,
        alert: false,
      ));
    }
  }
  final replay = data.result('get_capture_status');
  final started = deviceTime(replay?['started']);
  final filename = displayText(replay?['filename']);
  if (started != null && filename != null) {
    entries.add((
      title: '开始文件重放',
      detail: filename,
      source: '本地重放服务',
      time: started,
      icon: Icons.replay,
      alert: false,
    ));
  }
  return entries..sort((a, b) => b.time.compareTo(a.time));
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile(this.item);
  final _Activity item;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 19,
            color: item.alert
                ? ConsoleColors.warningOf(context)
                : colors.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleSmall),
                if (item.detail.isNotEmpty)
                  Text(item.detail, style: _quiet(context)),
                Text(
                  '${item.source} · ${displayTime(item.time)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
