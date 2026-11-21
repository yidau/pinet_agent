import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../mcp/device_panel.dart';
import '../mcp/tool_registry.dart';
import '../network.dart';
import 'phone_controls.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.session,
    required this.observations,
    required this.onOpenAi,
  });

  final DeviceSession? session;
  final Map<String, Json> observations;
  final VoidCallback onOpenAi;

  @override
  Widget build(BuildContext context) {
    final data = _DashboardData(session, observations);
    final system = data.result('get_system_info');
    final network = data.result('get_network_profile');
    final events = data.records('get_wireless_events', 'events');
    final hasKismetAlerts = data.tool('get_kismet_alerts') != null;
    final alertsTool = hasKismetAlerts
        ? 'get_kismet_alerts'
        : 'get_security_events';
    return _Dashboard(
      title: '网络概览',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final width = available >= 304
                ? (available - 16) / 3
                : available >= 200
                ? (available - 8) / 2
                : available;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: width,
                  child: _Metric(
                    icon: Icons.router_outlined,
                    label: '接入点',
                    count: data.count('get_access_points', 'access_points'),
                    state: data.state('get_access_points'),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _Metric(
                    icon: Icons.devices_outlined,
                    label: '客户端',
                    count: data.count('get_wireless_clients', 'clients'),
                    state: data.state('get_wireless_clients'),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _Metric(
                    icon: Icons.shield_outlined,
                    label: '安全告警',
                    count: data.count(
                      alertsTool,
                      hasKismetAlerts ? 'alerts' : 'events',
                    ),
                    state: data.state(alertsTool),
                  ),
                ),
              ],
            );
          },
        ),
        FilledButton.tonalIcon(
          onPressed: onOpenAi,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('打开 AI 分析'),
        ),
        _Panel(
          title: '设备信息',
          icon: Icons.memory_outlined,
          child: _Details(
            values: [
              ('主机名', _text(system?['hostname'])),
              ('系统', _text(system?['os'])),
              ('内核', _text(system?['kernel'])),
              ('架构', _text(system?['architecture'])),
            ],
            empty: data.state('get_system_info'),
          ),
        ),
        _Panel(
          title: '当前网络',
          icon: Icons.lan_outlined,
          child: _Details(
            values: [
              ('SSID', _text(network?['ssid'])),
              ('接口', _text(network?['interface'])),
              ('IP 地址', _text(network?['ip_address'])),
              ('网关', _text(network?['gateway'])),
            ],
            empty: data.state('get_network_profile'),
          ),
        ),
        _Panel(
          title: '最近网络事件',
          icon: Icons.event_note_outlined,
          child: events == null || events.isEmpty
              ? _QuietText(
                  events?.isEmpty == true
                      ? '没有观察到网络事件'
                      : data.state('get_wireless_events'),
                )
              : _RecordList(records: events.take(5).map(_eventRow).toList()),
        ),
      ],
    );
  }
}

class WirelessPage extends StatelessWidget {
  const WirelessPage({
    super.key,
    required this.session,
    required this.observations,
  });

  final DeviceSession? session;
  final Map<String, Json> observations;

  @override
  Widget build(BuildContext context) {
    final data = _DashboardData(session, observations);
    final accessPoints = data.records('get_access_points', 'access_points');
    final bluetooth = data.records('get_bluetooth_devices', 'devices');
    final clients = data.records('get_wireless_clients', 'clients');
    final channels = data.records('get_wifi_channels', 'channels');
    final events = data.records('get_wireless_events', 'events');
    final history = data.records('get_signal_history', 'history');
    final signals = <(String?, List<double>)>[];
    for (final device in history ?? const <Json>[]) {
      final records = device['samples'];
      if (records is! List) continue;
      final samples = [
        for (final sample in records.whereType<Json>())
          if (sample['rssi_dbm'] case final num value when value.isFinite)
            value.toDouble(),
      ];
      if (samples.isNotEmpty) signals.add((_text(device['name']), samples));
    }
    final kismet = session?.registry.kismet;
    final tools = [
      'get_access_points',
      if (data.tool('get_bluetooth_devices') != null) 'get_bluetooth_devices',
      'get_wireless_clients',
      'get_wifi_channels',
      'get_signal_history',
      'get_wireless_events',
    ];
    return _Dashboard(
      title: '无线环境',
      children: [
        if (session?.registry.phoneControl == true)
          _Panel(
            title: '无线扫描',
            icon: Icons.sensors,
            child: PhoneControls.radio(
              key: ObjectKey(session),
              session: session!,
            ),
          ),
        if (tools.any((name) => data.result(name)?['truncated'] == true))
          const _QuietText('设备仅返回了部分观测记录。以下列表和信道统计基于本次返回的数据。'),
        if (kismet?.sources.isEmpty == true &&
            kismet?.wirelessStatus == CapabilityStatus.degraded)
          const _Panel(
            title: '无线观测受限',
            icon: Icons.wifi_off_outlined,
            child: _QuietText(
              'Wireless monitoring is degraded: no supported capture source is available.',
            ),
          )
        else if (kismet?.sources.isEmpty == true &&
            kismet?.wirelessStatus == CapabilityStatus.error)
          _Panel(
            title: '无线观测出错',
            icon: Icons.error_outline,
            child: _QuietText(kismet?.reason ?? '设备未报告错误详情。'),
          )
        else if (data.allUnimplemented(tools))
          const _Panel(
            title: 'Wireless monitoring is not available yet.',
            icon: Icons.wifi_off_outlined,
            child: _QuietText('接入 Kismet 后可查看接入点、信号历史和无线活动。'),
          ),
        _Panel(
          title: 'Wi-Fi Networks',
          icon: Icons.router_outlined,
          child: accessPoints == null || accessPoints.isEmpty
              ? _QuietText(
                  accessPoints?.isEmpty == true
                      ? '没有观察到接入点'
                      : data.state('get_access_points'),
                )
              : _AccessPoints(records: accessPoints),
        ),
        _Panel(
          title: 'Bluetooth Devices',
          icon: Icons.bluetooth_outlined,
          child: bluetooth == null || bluetooth.isEmpty
              ? _QuietText(
                  bluetooth?.isEmpty == true
                      ? '此次主动扫描尚未记录到蓝牙设备'
                      : data.state('get_bluetooth_devices'),
                )
              : _RecordList(
                  records: [
                    for (final row in bluetooth)
                      (
                        _text(row['name']) ??
                            _text(row['address'] ?? row['mac']) ??
                            '蓝牙设备',
                        [
                          ?_sourceLabel(row['observation_source']),
                          ?_text(row['address'] ?? row['mac']),
                          ?_text(row['type']),
                          if (_text(row['rssi_dbm']) case final rssi?)
                            '$rssi dBm',
                          ?_observationTime(row['observed_at']),
                        ].join(' · '),
                      ),
                  ],
                ),
        ),
        _Panel(
          title: '信号历史',
          icon: Icons.show_chart,
          child: signals.isEmpty
              ? _QuietText(data.state('get_signal_history'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (name, samples) in signals) ...[
                      if (name != null) Text(name),
                      _SignalHistory(samples: samples),
                    ],
                  ],
                ),
        ),
        _Panel(
          title: '无线客户端',
          icon: Icons.devices_outlined,
          child: clients == null || clients.isEmpty
              ? _QuietText(
                  clients?.isEmpty == true
                      ? '没有观察到客户端'
                      : data.state('get_wireless_clients'),
                )
              : _RecordList(
                  records: clients.map((record) {
                    final mac = _text(record['mac']);
                    return (
                      _text(record['name']) ?? mac ?? '无线客户端',
                      [
                        if (mac != null && mac != record['name']) mac,
                        if (_text(record['channel']) case final channel?)
                          '信道 $channel',
                        if (_text(record['rssi_dbm']) case final rssi?)
                          '$rssi dBm',
                        ?_text(record['ap_bssid']),
                      ].join(' · '),
                    );
                  }).toList(),
                ),
        ),
        _Panel(
          title: '信道',
          icon: Icons.stacked_bar_chart,
          child: channels == null || channels.isEmpty
              ? _QuietText(data.state('get_wifi_channels'))
              : _RecordList(
                  records: channels.map((record) {
                    final channel = _text(record['channel']);
                    final frequency = _text(record['frequency_mhz']);
                    final count = _text(record['device_count']);
                    return (
                      channel == null ? '信道' : '信道 $channel',
                      [
                        if (count != null) '$count 台设备',
                        if (frequency != null) '$frequency MHz',
                      ].join(' · '),
                    );
                  }).toList(),
                ),
        ),
        _Panel(
          title: '无线活动',
          icon: Icons.monitor_heart_outlined,
          child: events == null || events.isEmpty
              ? _QuietText(
                  events?.isEmpty == true
                      ? '没有观察到无线活动'
                      : data.state('get_wireless_events'),
                )
              : _RecordList(records: events.map(_eventRow).toList()),
        ),
      ],
    );
  }
}

class CapturesPage extends StatelessWidget {
  const CapturesPage({
    super.key,
    required this.session,
    required this.observations,
  });

  final DeviceSession? session;
  final Map<String, Json> observations;

  @override
  Widget build(BuildContext context) {
    final data = _DashboardData(session, observations);
    final tasks = data.records('list_captures', 'tasks');
    final captures = data.records('list_captures', 'captures');
    final replay = data.result('get_capture_status');
    final protocols = data.records(
      'analyze_protocol_distribution',
      'protocols',
    );
    final report = data.result('analyze_packet_capture');
    const tools = ['list_captures', 'get_capture_metadata'];
    return _Dashboard(
      title: '报文采集',
      children: [
        if (data.allUnimplemented(tools))
          const _Panel(
            title: '报文采集尚未实现',
            icon: Icons.layers_clear_outlined,
            child: _QuietText('采集服务接入后可在这里查看 PCAP 文件与分析结果。'),
          ),
        if (session?.registry.phoneControl == true)
          _Panel(
            title: '文件重放',
            icon: Icons.replay_outlined,
            child: PhoneControls.captures(
              key: ObjectKey(session),
              session: session!,
              files: captures ?? const [],
            ),
          )
        else if (data.tool('get_capture_status') != null)
          _Panel(
            title: '文件重放',
            icon: Icons.replay_outlined,
            child: _Details(
              values: [
                ('状态', _text(replay?['state'])),
                ('文件', _text(replay?['filename'])),
                ('数据源', _text(replay?['datasource'])),
                ('说明', _text(replay?['reason'])),
              ],
              empty: data.state('get_capture_status'),
            ),
          )
        else
          _Panel(
            title: '抓包任务',
            icon: Icons.pending_actions_outlined,
            child: tasks == null || tasks.isEmpty
                ? _QuietText(
                    tasks?.isEmpty == true
                        ? '没有抓包任务'
                        : data.state('list_captures'),
                  )
                : _RecordList(
                    records: tasks.map((task) {
                      return (
                        _text(task['name']) ?? _text(task['id']) ?? '抓包任务',
                        _text(task['status']) ?? '',
                      );
                    }).toList(),
                  ),
          ),
        _Panel(
          title: '离线文件',
          icon: Icons.folder_open_outlined,
          child: captures == null || captures.isEmpty
              ? _QuietText(
                  captures?.isEmpty == true
                      ? '离线目录中没有实验文件'
                      : data.state('list_captures'),
                )
              : Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final file in captures)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            _text(file['filename'] ?? file['name']) ?? '实验文件',
                          ),
                          subtitle: Text(
                            [
                              ?_text(file['format']),
                              ?_bytes(file['size_bytes']),
                              ?_text(
                                file['modified_at'] ?? file['captured_at'],
                              ),
                            ].join(' · '),
                          ),
                          onTap:
                              file['id'] is String &&
                                  data
                                          .tool('get_capture_metadata')
                                          ?.isCallable ==
                                      true
                              ? () => _openMetadata(
                                  context,
                                  session!,
                                  file['id'] as String,
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
        ),
        _Panel(
          title: '协议统计',
          icon: Icons.bar_chart_outlined,
          child: protocols == null || protocols.isEmpty
              ? _QuietText(data.state('analyze_protocol_distribution'))
              : _RecordList(
                  records: protocols.map((record) {
                    final packets = _text(record['packet_count']);
                    return (
                      _text(record['protocol']) ?? '协议',
                      packets == null ? '' : '$packets 个报文',
                    );
                  }).toList(),
                ),
        ),
        _Panel(
          title: '分析报告',
          icon: Icons.description_outlined,
          child: _QuietText(
            _text(report?['summary']) ?? data.state('analyze_packet_capture'),
          ),
        ),
      ],
    );
  }

  Future<void> _openMetadata(
    BuildContext context,
    DeviceSession session,
    String id,
  ) {
    final query = session
        .callTool('get_capture_metadata', {'capture_id': id})
        .onError<FormatException>(
          (error, _) => {'ok': false, 'message': error.message},
        );
    return showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('文件元信息'),
        content: FutureBuilder<Json>(
          future: query,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (!session.isActive) return const Text('设备已断开');
            final file = snapshot.data;
            if (file == null || file['ok'] == false) {
              return Text(_text(file?['message']) ?? '无法读取文件元信息');
            }
            return _Details(
              values: [
                ('文件', _text(file['filename'])),
                ('格式', _text(file['format'])),
                ('大小', _bytes(file['size_bytes'])),
                ('修改时间', _text(file['modified_at'])),
                ('说明', _text(file['reason'])),
              ],
              empty: '设备未报告文件元信息',
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _DashboardData {
  const _DashboardData(this.session, this.observations);

  final DeviceSession? session;
  final Map<String, Json> observations;

  DeviceTool? tool(String name) => session?.registry[name];

  bool allUnimplemented(List<String> names) =>
      names.every((name) => tool(name)?.status == CapabilityStatus.unavailable);

  Json? result(String name) {
    if (tool(name)?.status != CapabilityStatus.available) return null;
    final result = observations[name];
    if (result == null || result['ok'] == false) return null;
    return result['data'] is Json ? result['data'] as Json : result;
  }

  List<Json>? records(String name, String field) {
    final value = result(name)?[field];
    return value is List && value.every((entry) => entry is Json)
        ? value.cast<Json>()
        : null;
  }

  String? count(String name, String field) {
    final observation = result(name);
    final value = observation?['total'] ?? observation?['count'];
    if (value is int && value >= 0) return value.toString();
    final length = records(name, field)?.length;
    if (length == null) return null;
    return observation?['truncated'] == true ? '≥ $length' : length.toString();
  }

  String state(String name) {
    if (session == null) return '设备未连接';
    final capability = tool(name);
    final status = capability?.status ?? CapabilityStatus.unknown;
    if (status != CapabilityStatus.available) {
      return [capabilityStatusLabel(status), ?capability?.reason].join(' · ');
    }
    final result = observations[name];
    if (result?['ok'] == false) {
      return _text(result?['message']) ?? '读取失败';
    }
    return '暂无数据';
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ),
      for (final child in children)
        Padding(padding: const EdgeInsets.only(top: 12), child: child),
    ],
  );
}

class _Surface extends StatelessWidget {
  const _Surface({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.count,
    required this.state,
  });

  final IconData icon;
  final String label;
  final String? count;
  final String state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Surface(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 20),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.labelMedium),
          Text(count ?? '—', style: theme.textTheme.titleLarge),
          if (count == null) _QuietText(state) else const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.values, required this.empty});

  final List<(String, String?)> values;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final actual = values.where((value) => value.$2 != null);
    if (actual.isEmpty) return _QuietText(empty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in actual)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 64, child: _QuietText(label)),
                Expanded(child: Text(value!)),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuietText extends StatelessWidget {
  const _QuietText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.records});

  final List<(String, String)> records;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var index = 0; index < records.length; index++) ...[
        if (index > 0) const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(records[index].$1),
              if (records[index].$2.isNotEmpty) _QuietText(records[index].$2),
            ],
          ),
        ),
      ],
    ],
  );
}

class _AccessPoints extends StatelessWidget {
  const _AccessPoints({required this.records});

  final List<Json> records;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      horizontalMargin: 0,
      columnSpacing: 16,
      columns: const [
        DataColumn(label: Text('SSID / BSSID')),
        DataColumn(label: Text('观测来源')),
        DataColumn(label: Text('信道')),
        DataColumn(label: Text('RSSI')),
        DataColumn(label: Text('认证')),
        DataColumn(label: Text('频率')),
        DataColumn(label: Text('观测时间')),
      ],
      rows: [
        for (final record in records)
          DataRow(
            cells: [
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      record['ssid'] == ''
                          ? '隐藏 SSID'
                          : _text(record['ssid'] ?? record['name']) ?? '—',
                    ),
                    if (_text(record['bssid'] ?? record['mac'])
                        case final bssid?)
                      _QuietText(bssid),
                  ],
                ),
              ),
              DataCell(
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_observationSources(record)),
                    if (record['kismet_reported'] == false)
                      const _QuietText('扫描报告未写入 Kismet'),
                  ],
                ),
              ),
              DataCell(Text(_text(record['channel']) ?? '—')),
              DataCell(
                Text(switch (_text(record['rssi_dbm'] ?? record['rssi'])) {
                  final String rssi => '$rssi dBm',
                  null => '—',
                }),
              ),
              DataCell(Text(_text(record['security']) ?? '未知')),
              DataCell(
                Text(switch (_text(record['frequency_mhz'])) {
                  final String mhz => '$mhz MHz',
                  null => '—',
                }),
              ),
              DataCell(Text(_observationTime(record['observed_at']) ?? '—')),
            ],
          ),
      ],
    ),
  );
}

class _SignalHistory extends StatelessWidget {
  const _SignalHistory({required this.samples});

  final List<double> samples;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _QuietText('最新信号 ${samples.last.toStringAsFixed(0)} dBm'),
      const SizedBox(height: 8),
      SizedBox(
        height: 88,
        width: double.infinity,
        child: CustomPaint(
          painter: _SignalLine(samples, Theme.of(context).colorScheme.primary),
        ),
      ),
    ],
  );
}

class _SignalLine extends CustomPainter {
  const _SignalLine(this.samples, this.color);

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final low = samples.reduce(math.min);
    final high = samples.reduce(math.max);
    final paint = Paint()..color = color;
    final path = Path();
    for (var index = 0; index < samples.length; index++) {
      final span = math.max(0.0, size.width - 6);
      final x = samples.length == 1
          ? size.width / 2
          : 3 + index * span / (samples.length - 1);
      final fraction = high == low
          ? 0.5
          : (samples[index] - low) / (high - low);
      final y = 4 + (1 - fraction) * (size.height - 8);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      if (index == samples.length - 1) {
        canvas.drawCircle(Offset(x, y), 3, paint);
      }
    }
    canvas.drawPath(
      path,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SignalLine oldDelegate) =>
      oldDelegate.samples != samples || oldDelegate.color != color;
}

(String, String) _eventRow(Json event) => (
  _text(event['message']) ?? _text(event['type']) ?? '网络事件',
  _text(event['timestamp']) ?? '',
);

String? _text(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text.trim(),
  final num number when number.isFinite => number.toString(),
  _ => null,
};

String? _sourceLabel(Object? value) => switch (value) {
  'managed_scan' => 'Managed Scan',
  'monitor_mode' => 'Monitor Mode',
  'bluetooth_scan' => 'Active Scan',
  'pcap_replay' => 'PCAP Replay',
  _ => _text(value),
};

String _observationSources(Json record) {
  final origins = record['observation_sources'];
  if (origins is List) {
    final labels = origins.map(_sourceLabel).nonNulls.toSet();
    if (labels.isNotEmpty) return labels.join(' / ');
  }
  return _sourceLabel(record['observation_source']) ?? '未报告';
}

String? _observationTime(Object? value) {
  if (value is int && value >= 0 && value < 10000000000) {
    return DateTime.fromMillisecondsSinceEpoch(
      value * 1000,
      isUtc: true,
    ).toIso8601String();
  }
  return _text(value);
}

String? _bytes(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '$value B';
}
