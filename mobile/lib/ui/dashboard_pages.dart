import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../mcp/device_panel.dart';
import '../mcp/tool_registry.dart';
import '../network.dart';

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
                    count: data.count('get_security_events', 'events'),
                    state: data.state('get_security_events'),
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
    final clients = data.records('get_wireless_clients', 'clients');
    final channels = data.records('get_wifi_channels', 'channels');
    final events = data.records('get_wireless_events', 'events');
    final history = data.records('get_signal_history', 'history');
    final samples = <double>[
      for (final entry in history ?? const <Json>[])
        if ((entry['rssi_dbm'] ?? entry['rssi']) case final num value
            when value.isFinite)
          value.toDouble(),
    ];
    const tools = [
      'get_access_points',
      'get_wireless_clients',
      'get_wifi_channels',
      'get_signal_history',
      'get_wireless_events',
    ];
    return _Dashboard(
      title: '无线环境',
      children: [
        if (data.allUnimplemented(tools))
          const _Panel(
            title: 'Wireless monitoring is not available yet.',
            icon: Icons.wifi_off_outlined,
            child: _QuietText('接入 Kismet 后可查看接入点、信号历史和无线活动。'),
          ),
        _Panel(
          title: '信号历史',
          icon: Icons.show_chart,
          child: samples.isEmpty
              ? _QuietText(data.state('get_signal_history'))
              : _SignalHistory(samples: samples),
        ),
        _Panel(
          title: '接入点',
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
                      [_text(record['ap_bssid'])].nonNulls.join(' · '),
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
                    return (
                      channel == null ? '信道' : '信道 $channel',
                      frequency == null ? '' : '$frequency MHz',
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
          title: 'PCAP 文件',
          icon: Icons.folder_open_outlined,
          child: captures == null || captures.isEmpty
              ? _QuietText(
                  captures?.isEmpty == true
                      ? '没有 PCAP 文件'
                      : data.state('list_captures'),
                )
              : _RecordList(
                  records: captures.map((capture) {
                    return (
                      _text(capture['filename']) ??
                          _text(capture['name']) ??
                          'PCAP 文件',
                      [
                        _bytes(capture['size_bytes']),
                        _text(capture['captured_at']),
                      ].nonNulls.join(' · '),
                    );
                  }).toList(),
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

  int? count(String name, String field) {
    final value = result(name)?['count'];
    if (value is int && value >= 0) return value;
    return records(name, field)?.length;
  }

  String state(String name) {
    if (session == null) return '设备未连接';
    final status = tool(name)?.status ?? CapabilityStatus.unknown;
    if (status != CapabilityStatus.available) {
      return capabilityStatusLabel(status);
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
  final int? count;
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
          Text(count?.toString() ?? '—', style: theme.textTheme.titleLarge),
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
        DataColumn(label: Text('信道')),
        DataColumn(label: Text('RSSI')),
        DataColumn(label: Text('认证')),
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
                    Text(_text(record['ssid']) ?? '—'),
                    if (_text(record['bssid']) case final bssid?)
                      _QuietText(bssid),
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
              DataCell(Text(_text(record['security']) ?? '—')),
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

String? _bytes(Object? value) {
  if (value is! num || !value.isFinite || value < 0) return null;
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '$value B';
}
