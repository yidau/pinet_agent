import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../mcp/device_panel.dart' show capabilityStatusLabel;
import '../mcp/tool_registry.dart';
import '../network.dart';
import 'console_style.dart';
import 'phone_controls.dart';
import 'wifi_networks.dart';
import 'workspace_data.dart';

enum _Area {
  aps('无线网络'),
  clients('客户端'),
  bluetooth('蓝牙');

  const _Area(this.label);
  final String label;
}

enum _WifiMode {
  networks('网络'),
  aps('接入点'),
  channels('信道');

  const _WifiMode(this.label);
  final String label;
}

const _sourceNames = {
  'managed_scan': 'Managed Scan',
  'monitor_mode': 'Monitor Mode',
  'bluetooth_scan': 'Bluetooth Active Scan',
  'pcap_replay': 'PCAP Replay',
  'kismet': 'Kismet',
};
const _sourceDescriptions = {
  'managed_scan': '普通扫描 · 单次采样附近接入点',
  'monitor_mode': '监听模式 · 依赖支持监听的网卡和运行中的数据源',
  'bluetooth_scan': '主动发现 · 观测附近的蓝牙设备',
  'pcap_replay': '离线重放 · 读取文件中的已有记录',
};

String? _text(Object? value) => switch (value) {
  String s when s.trim().isNotEmpty => s.trim(),
  num n when n.isFinite => n.toString(),
  _ => null,
};

String? _when(Object? raw) {
  final time = deviceTime(raw);
  return time == null ? null : displayTime(time);
}

String _source(Json row, [Object? fallback]) {
  final keys = row['observation_sources'];
  final names = keys is List ? keys.whereType<String>().toList() : <String>[];
  if (names.isEmpty) {
    final source = _text(
      row['observation_source'] ?? row['source'] ?? fallback,
    );
    if (source != null) names.add(source);
  }
  return names.isEmpty
      ? '来源未报告'
      : names.map((key) => _sourceNames[key] ?? key).join(' / ');
}

String _name(Json row) {
  return wifiSsid(row) ?? '隐藏 SSID';
}

String _security(Json row) {
  final value = _text(row['security']);
  if (value == null) return '认证未知';
  final upper = value.toUpperCase();
  if (upper == '[ESS]' || upper == 'OPEN') return '开放';
  if (upper.contains('OWE')) return '增强开放（OWE）';
  if (upper.contains('RSN') && upper.contains('SAE')) {
    return upper.contains('PSK') ? 'WPA2 / WPA3' : 'WPA3';
  }
  if (upper.contains('RSN') && upper.contains('PSK')) return 'WPA2';
  if (upper.contains('RSN')) return 'RSN';
  if (upper == '[WPA-UNKNOWN][ESS]') return 'WPA';
  return value;
}

String _emptyReason(WorkspaceData data, String tool, String empty) =>
    data.result(tool) == null ? data.reason(tool) : empty;

class WirelessWorkspace extends StatefulWidget {
  const WirelessWorkspace({
    super.key,
    required this.session,
    required this.observations,
  });
  final DeviceSession? session;
  final Map<String, Json> observations;

  @override
  State<WirelessWorkspace> createState() => _WirelessWorkspaceState();
}

class _WirelessWorkspaceState extends State<WirelessWorkspace> {
  _Area _area = _Area.aps;
  _WifiMode _mode = _WifiMode.networks;
  String? _bandFilter;

  @override
  void didUpdateWidget(WirelessWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session)) _bandFilter = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = WorkspaceData(widget.session, widget.observations);
    final (tool, field, title, empty) = switch (_area) {
      _Area.aps => (
        'get_access_points',
        'access_points',
        switch (_mode) {
          _WifiMode.networks => '附近网络',
          _WifiMode.aps => '附近接入点',
          _WifiMode.channels => '观测信道',
        },
        '本次扫描未观测到接入点。',
      ),
      _Area.clients => (
        'get_wireless_clients',
        'clients',
        '观测客户端',
        '本次监听未观测到客户端。',
      ),
      _Area.bluetooth => (
        'get_bluetooth_devices',
        'devices',
        '蓝牙设备',
        '此次主动发现尚未记录到设备。',
      ),
    };
    final report = data.result(tool);
    final rows = data.rows(tool, field);
    final wifi = _area == _Area.aps && report != null && rows != null
        ? WifiNetworks(report, rows)
        : null;
    final bands = {
      for (final row in wifi?.byBssid.values ?? const <Json>[]) ?wifiBand(row),
    };
    final filterBand = bands.contains(_bandFilter) && _area == _Area.aps
        ? _bandFilter
        : null;
    final groups = wifi?.groups(filterBand) ?? const <WifiNetwork>[];
    final visible = wifi == null
        ? rows
        : [for (final group in groups) ...group.aps];
    final channels = <String, List<Json>>{};
    if (wifi != null) {
      for (final row in visible!) {
        final channel = wifiChannel(row);
        if (channel != null) (channels[channel] ??= []).add(row);
      }
    }
    final sortedChannels = channels.keys.toList()
      ..sort((a, b) {
        final first = int.tryParse(a), second = int.tryParse(b);
        return first != null && second != null
            ? first.compareTo(second)
            : a.compareTo(b);
      });
    final length = switch ((_area, _mode)) {
      (_Area.aps, _WifiMode.networks) => groups.length,
      (_Area.aps, _WifiMode.channels) => channels.length,
      _ => visible?.length ?? 0,
    };
    final time = _when(report?['timestamp']);
    final availableSources = {
      for (final row in rows ?? const <Json>[]) _source(row, report?['source']),
    };
    final hasOperator = widget.session?.registry.phoneControl == true;
    final items = <Widget>[
      SegmentedButton<_Area>(
        expandedInsets: EdgeInsets.zero,
        segments: [
          for (final item in _Area.values)
            ButtonSegment(value: item, label: Text(item.label)),
        ],
        selected: {_area},
        showSelectedIcon: false,
        onSelectionChanged: (value) => setState(() => _area = value.single),
      ),
      const SizedBox(height: 12),
      ConsoleCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: Icon(Icons.sensors, color: theme.colorScheme.primary),
          title: const Text('观测来源'),
          subtitle: Text(
            availableSources.isEmpty
                ? '查看各数据源状态'
                : availableSources.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            for (final entry in _sourceDescriptions.entries)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _SourceStatus(
                  name: _sourceNames[entry.key]!,
                  description: entry.value,
                  state: widget.session?.registry.kismet?.sources[entry.key],
                ),
              ),
          ],
        ),
      ),
      if (hasOperator && _area != _Area.clients) ...[
        const SizedBox(height: 12),
        ConsoleCard(
          child: PhoneControls.radio(
            key: ValueKey((widget.session, _area)),
            session: widget.session!,
            showBluetooth: _area == _Area.bluetooth,
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (_area == _Area.aps) ...[
        SegmentedButton<_WifiMode>(
          expandedInsets: EdgeInsets.zero,
          segments: [
            for (final mode in _WifiMode.values)
              ButtonSegment(value: mode, label: Text(mode.label)),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (modes) => setState(() => _mode = modes.single),
        ),
        const SizedBox(height: 12),
      ],
      ConsoleHeading(
        title,
        trailing: rows == null
            ? null
            : Text(
                '${report?['truncated'] == true ? '≥ ' : ''}$length',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
      ),
      if (wifi != null)
        Text(
          '${groups.length} 个网络 · ${visible!.length} 个 BSSID · ${channels.length} 个已知信道',
          style: theme.textTheme.bodySmall,
        ),
      if (time != null) Text('读取于 $time', style: theme.textTheme.bodySmall),
      if (_area == _Area.aps && bands.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            children: [
              for (final band in <String?>[
                null,
                ...['2.4 GHz', '5 GHz', '6 GHz'].where(bands.contains),
              ])
                ChoiceChip(
                  label: Text(band ?? '全部'),
                  selected: filterBand == band,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _bandFilter = band),
                ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      if (report?['truncated'] == true) const Text('设备返回了部分记录。'),
      if (rows == null || length == 0)
        ConsoleCard(
          child: _EmptyState(
            icon: switch (_area) {
              _Area.aps => Icons.wifi_find_outlined,
              _Area.clients => Icons.devices_outlined,
              _Area.bluetooth => Icons.bluetooth_searching,
            },
            title: switch (_area) {
              _Area.aps => switch (_mode) {
                _WifiMode.networks => '暂无网络记录',
                _WifiMode.aps => '暂无接入点记录',
                _WifiMode.channels => '暂无信道记录',
              },
              _Area.clients => '暂无客户端记录',
              _Area.bluetooth => '暂无蓝牙观测',
            },
            message: _emptyReason(
              data,
              tool,
              wifi != null && wifi.byBssid.isEmpty && rows!.isNotEmpty
                  ? '报告中的记录缺少有效 BSSID，无法识别接入点。'
                  : _area == _Area.aps && _mode == _WifiMode.channels
                  ? '当前接入点观测中没有可识别的信道。'
                  : empty,
            ),
          ),
        ),
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length + length + 1,
      itemBuilder: (context, i) {
        if (i < items.length) return items[i];
        final index = i - items.length;
        if (index == length) {
          return _area == _Area.aps
              ? _EnvironmentReports(data: data)
              : const SizedBox.shrink();
        }
        if (_area == _Area.aps && _mode == _WifiMode.networks) {
          final group = groups[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _NetworkTile(
              group: group,
              onTap: () => _openNetwork(context, group, data, report!),
            ),
          );
        }
        if (_area == _Area.aps && _mode == _WifiMode.channels) {
          final channel = sortedChannels[index], aps = channels[channel]!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ConsoleCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                title: Text('信道 $channel'),
                subtitle: Text('${aps.length} 个 BSSID'),
                children: [
                  for (final ap in aps) _apTile(context, ap, data, report!),
                ],
              ),
            ),
          );
        }
        final row = visible![index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _ObservationTile(
            area: _area,
            row: row,
            source: _source(row, report?['source']),
            onTap: _area == _Area.aps
                ? () => _openAp(context, row, data, report!)
                : null,
          ),
        );
      },
    );
  }
}

void _openAp(BuildContext context, Json ap, WorkspaceData data, Json report) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          _ApPage(row: ap, session: data.session!, view: data, report: report),
    ),
  );
}

Widget _apTile(
  BuildContext context,
  Json ap,
  WorkspaceData data,
  Json report,
) => _ObservationTile(
  area: _Area.aps,
  row: ap,
  source: _source(ap, report['source']),
  onTap: () => _openAp(context, ap, data, report),
);

void _openNetwork(
  BuildContext context,
  WifiNetwork group,
  WorkspaceData data,
  Json report,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (pageContext) => Scaffold(
        appBar: AppBar(title: Text(group.title)),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: group.aps.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) => index == 0
              ? const ConsoleHeading('接入点')
              : _apTile(pageContext, group.aps[index - 1], data, report),
        ),
      ),
    ),
  );
}

class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.group, required this.onTap});
  final WifiNetwork group;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final security = group.aps.map(_security).toSet().join(' · ');
    final strongest = group.strongest, weakest = group.weakest;
    return ConsoleCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wifi, size: 21, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (strongest != null) _SignalReading(rssi: strongest),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  Text(
                    '${group.aps.length} 个 BSSID',
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    group.channels.isEmpty
                        ? '信道未报告'
                        : '${group.channels.length} 个信道',
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(security, style: theme.textTheme.labelMedium),
                ],
              ),
              if (strongest != null)
                Text(
                  weakest == strongest
                      ? '最强信号 $strongest dBm'
                      : '最强 $strongest dBm · 最弱 $weakest dBm',
                  style: theme.textTheme.bodySmall,
                ),
              Text(
                group.lastSeen == null
                    ? '最近观测时间未报告'
                    : '最近观测 ${displayTime(group.lastSeen!)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceStatus extends StatelessWidget {
  const _SourceStatus({
    required this.name,
    required this.description,
    required this.state,
  });
  final String name, description;
  final ({CapabilityStatus status, String? reason})? state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              Text(
                capabilityStatusLabel(
                  state?.status ?? CapabilityStatus.unknown,
                ),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          Text(description, style: theme.textTheme.bodySmall),
          if (_text(state?.reason) case final String reason)
            Text(reason, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 5),
              Text(message, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _ObservationTile extends StatelessWidget {
  const _ObservationTile({
    required this.area,
    required this.row,
    required this.source,
    this.onTap,
  });
  final _Area area;
  final Json row;
  final String source;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = _text(row['bssid'] ?? row['mac'] ?? row['address']);
    final isAp = area == _Area.aps;
    final name = isAp
        ? address ?? _name(row)
        : _text(row['name']) ??
              address ??
              (area == _Area.clients ? '无线客户端' : '蓝牙设备');
    final rssi = row['rssi_dbm'] ?? row['rssi'];
    final time = _when(row['last_seen'] ?? row['observed_at']);
    final firstSeen = isAp ? _when(row['first_seen']) : null;
    final icon = switch (area) {
      _Area.aps => Icons.wifi_rounded,
      _Area.clients => Icons.devices,
      _Area.bluetooth => Icons.bluetooth,
    };
    final channel = _text(row['channel']);
    final labels = <String>[
      if (channel != null) 'Ch $channel',
      if (isAp) _security(row),
      if (_text(row['ap_bssid']) case final String ap) '接入 $ap',
      if (!isAp) ?_text(row['type']),
      source,
    ];
    return ConsoleCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 21, color: theme.colorScheme.primary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (rssi is num && rssi.isFinite) _SignalReading(rssi: rssi),
                  if (isAp) const Icon(Icons.chevron_right, size: 18),
                ],
              ),
              if (address != null && address != name)
                Text(
                  address,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (isAp) Text(_name(row), style: theme.textTheme.bodySmall),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 3,
                children: [
                  for (final label in labels)
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: label == '开放'
                            ? ConsoleColors.warningOf(context)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (firstSeen != null)
                Text('首次观测 $firstSeen', style: theme.textTheme.bodySmall),
              if (time != null)
                Text('最近观测 $time', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalReading extends StatelessWidget {
  const _SignalReading({required this.rssi});
  final num rssi;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lit = rssi >= -55
        ? 4
        : rssi >= -67
        ? 3
        : rssi >= -80
        ? 2
        : 1;
    final dbm = '${rssi.toStringAsFixed(rssi.truncate() == rssi ? 0 : 1)} dBm';
    return Semantics(
      label: '接收信号强度 $dbm',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < 4; i++)
                Container(
                  width: 3,
                  height: 4.0 + 3.0 * i,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: i < lit
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
          Text(dbm, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _EnvironmentReports extends StatelessWidget {
  const _EnvironmentReports({required this.data});
  final WorkspaceData data;
  @override
  Widget build(BuildContext context) {
    final channels = data.rows('get_wifi_channels', 'channels') ?? const [];
    final events = data.rows('get_wireless_events', 'events') ?? const [];
    if (channels.isEmpty && events.isEmpty) return const SizedBox.shrink();
    return ConsoleCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        title: const Text('信道与无线活动'),
        children: [
          for (final row in channels)
            if (_text(row['channel']) case final String ch)
              ListTile(
                title: Text('信道 $ch'),
                subtitle: Text(
                  [
                    if (_text(row['device_count']) case final String n)
                      '$n 台设备',
                    if (_text(row['frequency_mhz']) case final String f)
                      '$f MHz',
                  ].join(' · '),
                ),
              ),
          for (final row in events) _EventRow(event: row),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final Json event;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      Icons.notifications_outlined,
      color: ConsoleColors.warningOf(context),
    ),
    title: Text(_text(event['type']) ?? '无线事件'),
    subtitle: Text(
      [?_text(event['message']), ?_when(event['timestamp'])].join('\n'),
    ),
  );
}

class _ApPage extends StatefulWidget {
  const _ApPage({
    required this.row,
    required this.session,
    required this.view,
    required this.report,
  });
  final Json row, report;
  final DeviceSession session;
  final WorkspaceData view;
  @override
  State<_ApPage> createState() => _ApPageState();
}

class _ApPageState extends State<_ApPage> {
  late final Future<Json?> details = _loadDetails();

  Future<Json?> _loadDetails() async {
    if (!widget.session.isActive ||
        widget.session.registry['get_ap_details']?.isCallable != true) {
      return null;
    }
    final id = _text(widget.row['id']) ?? wifiBssid(widget.row);
    if (id == null) return null;
    try {
      return await widget.session.callTool('get_ap_details', {'ap_id': id});
    } on FormatException catch (error) {
      return {'ok': false, 'message': error.message};
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('观测历史')),
    body: FutureBuilder<Json?>(
      future: details,
      builder: (context, snapshot) {
        final active = widget.session.isActive;
        final answer = active ? snapshot.data : null;
        final payload = answer?['data'] is Json
            ? answer!['data'] as Json
            : answer;
        final fresh = payload?['access_point'];
        final row = fresh is Json ? {...widget.row, ...fresh} : widget.row;
        final view = widget.view;
        final time = _when(row['last_seen'] ?? row['observed_at']);
        final reportTime = _when(
          answer?['timestamp'] ?? widget.report['timestamp'],
        );
        final channel = _text(row['channel']);
        final frequency = _text(row['frequency_mhz']);
        final mac = _text(row['bssid'] ?? row['mac']);
        final identifier = _text(row['id']);
        final matches = <String>{
          if (mac != null) mac.toLowerCase(),
          if (identifier != null) identifier.toLowerCase(),
          if (row['kismet_device_ids'] case final List keys)
            for (final key in keys.whereType<String>()) key.toLowerCase(),
        };
        bool exact(Object? value) =>
            value is String && matches.contains(value.toLowerCase());
        final related = payload?['related_bssids'] ?? row['related_bssids'];
        final relatedAddresses = {
          if (related is List)
            for (final value in related.whereType<String>())
              if (wifiBssid({'bssid': value}) case final String address
                  when !exact(address))
                address,
        };
        final serverHistory = payload?['observations'];
        final records = _apObservations(
          serverHistory,
          widget.report,
          view.rows('get_signal_history', 'history') ?? const [],
          exact,
        );
        final samples = records
            .where(
              (p) => p['rssi_dbm'] is num && (p['rssi_dbm'] as num).isFinite,
            )
            .toList();
        final events = [
          for (final e
              in view.rows('get_wireless_events', 'events') ?? const <Json>[])
            if (exact(e['bssid']) ||
                exact(e['ap_bssid']) ||
                exact(e['ap_id']) ||
                exact(e['device_id']) ||
                (e['device_macs'] is List &&
                    (e['device_macs'] as List).any(exact)))
              e,
        ];
        final pairs = <(String, String)>[
          ('BSSID', mac ?? '未报告'),
          ('信道', channel ?? '未报告'),
          ('频率', frequency == null ? '未报告' : '$frequency MHz'),
          ('认证', _security(row)),
          if (_text(row['security']) case final String raw) ('安全配置', raw),
          ('信号强度', row['rssi_dbm'] is num ? '${row['rssi_dbm']} dBm' : '未报告'),
          ('观测来源', _source(row, payload?['source'] ?? widget.report['source'])),
          if (relatedAddresses.isNotEmpty)
            ('Kismet 关联 BSSID', relatedAddresses.join('\n')),
          ('首次观测', _when(row['first_seen']) ?? '数据源未提供'),
          ('最近观测', time ?? '数据源未提供'),
          if (reportTime != null) ('读取时间', reportTime),
        ];
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Semantics(
              header: true,
              child: Text(_name(row), style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 12),
            if (!active) const Text('设备已断开，以下为上次读取的数据。'),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            if (answer?['ok'] == false)
              Text(_text(answer?['message']) ?? '详情查询失败，显示列表记录。'),
            ConsoleCard(
              child: Column(
                children: [
                  for (final pair in pairs)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              pair.$1,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Expanded(flex: 4, child: SelectableText(pair.$2)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const ConsoleHeading('信号历史'),
            ConsoleCard(
              child: samples.isEmpty
                  ? const Text('当前记录没有同时标明观测时间和信号强度。')
                  : _History(points: samples),
            ),
            const SizedBox(height: 16),
            ConsoleHeading('观测记录', trailing: Text('${records.length} 条')),
            ConsoleCard(
              padding: EdgeInsets.zero,
              child: records.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('设备尚未提供带时间的观测。'),
                    )
                  : Column(
                      children: [
                        for (final record in records.reversed.take(3))
                          _HistoryRow(record: record),
                        if (records.length > 3)
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: Text(mac ?? '观测记录')),
                                  body: ListView.builder(
                                    itemCount: records.length,
                                    itemBuilder: (_, i) => _HistoryRow(
                                      record: records[records.length - 1 - i],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            child: Text('查看全部 ${records.length} 条记录'),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            const ConsoleHeading('相关事件'),
            ConsoleCard(
              child: events.isEmpty
                  ? Text(
                      _emptyReason(
                        view,
                        'get_wireless_events',
                        '当前事件中没有标明此接入点的记录。',
                      ),
                    )
                  : Column(
                      children: [for (final e in events) _EventRow(event: e)],
                    ),
            ),
            const SizedBox(height: 16),
            const ConsoleHeading('关联证据'),
            ConsoleCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('接入点列表 · get_access_points'),
                  if (fresh is Json) const Text('设备详情 · get_ap_details'),
                  if (serverHistory is List)
                    const Text('观测历史 · get_ap_details'),
                  if (serverHistory is! List &&
                      records.any((r) => r['_legacy_signal'] == true))
                    const Text('监听采样 · get_signal_history'),
                  if (events.isNotEmpty)
                    const Text('无线事件 · get_wireless_events'),
                  if (row['kismet_reported'] == false)
                    const Text('扫描报告未写入 Kismet'),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

List<Json> _apObservations(
  Object? history,
  Json report,
  List<Json> signalHistory,
  bool Function(Object?) matches,
) {
  final candidates = <Json>[];
  if (history is List) {
    candidates.addAll(history.whereType<Json>());
  } else {
    for (final record in signalHistory) {
      if (!matches(record['id']) && !matches(wifiBssid(record))) continue;
      if (record['samples'] case final List points) {
        for (final point in points.whereType<Json>()) {
          candidates.add({
            ...point,
            'observation_source':
                record['observation_source'] ?? 'monitor_mode',
            'sample_kind': 'rrd_peak',
            '_legacy_signal': true,
          });
        }
      }
    }
    if (report['access_points'] case final List aps) {
      for (final ap in aps.whereType<Json>()) {
        if (matches(wifiBssid(ap)) || matches(ap['id'])) {
          candidates.add({
            'rssi_dbm': ap['rssi_dbm'],
            'channel': ap['channel'],
            'timestamp': ap['observed_at'] ?? ap['last_seen'],
            'observation_source':
                ap['observation_source'] ?? ap['source'] ?? report['source'],
          });
        }
      }
    }
  }
  final unique = <(DateTime, String?), Json>{};
  for (final p in candidates) {
    final timestamp = deviceTime(p['timestamp']);
    if (timestamp != null) {
      unique[(timestamp, _text(p['observation_source'] ?? p['source']))] = p;
    }
  }
  return unique.values.toList()..sort(
    (a, b) =>
        deviceTime(a['timestamp'])!.compareTo(deviceTime(b['timestamp'])!),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});
  final Json record;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(_when(record['timestamp'])!),
    subtitle: Text(
      [
        _source(record),
        if (record['sample_kind'] == 'rrd_peak') '每秒峰值',
        if (record['rssi_dbm'] case final num value when value.isFinite)
          '$value dBm',
        if (wifiChannel(record) case final String ch) '信道 $ch',
      ].join(' · '),
    ),
  );
}

class _History extends StatefulWidget {
  const _History({required this.points});
  final List<Json> points;
  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  int? _selected;
  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final index = (_selected ?? points.length - 1).clamp(0, points.length - 1);
    final point = points[index];
    final theme = Theme.of(context);
    final values = [for (final p in points) (p['rssi_dbm'] as num).toDouble()];
    final times = [
      for (final p in points)
        deviceTime(p['timestamp'])!.millisecondsSinceEpoch,
    ];
    final low = values.reduce((a, b) => a < b ? a : b).floor(),
        high = values.reduce((a, b) => a > b ? a : b).ceil();
    final span = times.last - times.first;
    final locations = [
      for (int i = 0; i < points.length; i++)
        Offset(
          span == 0 ? .5 : (times[i] - times.first) / span,
          high == low ? .5 : (high - values[i]) / (high - low),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${points.map((p) => _source(p)).toSet().join(' / ')} · $low 至 $high dBm',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '信号与时间散点图，${points.length} 个实际样本。可用下方按钮逐点查看。',
          child: LayoutBuilder(
            builder: (context, size) => GestureDetector(
              onTapUp: (tap) {
                final x = ((tap.localPosition.dx - 5) / (size.maxWidth - 10))
                    .clamp(0, 1);
                var closest = 0;
                for (var i = 1; i < locations.length; i++) {
                  if ((locations[i].dx - x).abs() <
                      (locations[closest].dx - x).abs()) {
                    closest = i;
                  }
                }
                setState(() => _selected = closest);
              },
              child: CustomPaint(
                size: Size(size.maxWidth, 86),
                painter: _SamplesPainter(locations, index, theme.colorScheme),
              ),
            ),
          ),
        ),
        Text(
          '${_when(points.first['timestamp'])} — ${_when(points.last['timestamp'])}',
          style: theme.textTheme.bodySmall,
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: '上一个采样点',
              onPressed: index == 0
                  ? null
                  : () => setState(() => _selected = index - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${point['rssi_dbm']} dBm · ${_when(point['timestamp'])}'),
            IconButton(
              tooltip: '下一个采样点',
              onPressed: index + 1 >= points.length
                  ? null
                  : () => setState(() => _selected = index + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

class _SamplesPainter extends CustomPainter {
  const _SamplesPainter(this.samples, this.selected, this.colors);
  final List<Offset> samples;
  final int selected;
  final ColorScheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colors.outlineVariant;
    for (final y in [5.0, size.height / 2, size.height - 5]) {
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y), paint);
    }
    for (int i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final pos = Offset(
        5 + sample.dx * (size.width - 10),
        5 + sample.dy * (size.height - 10),
      );
      paint.color = i == selected ? colors.primary : colors.onSurfaceVariant;
      canvas.drawCircle(pos, i == selected ? 4.5 : 2.3, paint);
      if (i == selected) {
        canvas.drawCircle(pos, 1.6, Paint()..color = colors.surface);
      }
    }
  }

  @override
  bool shouldRepaint(_SamplesPainter old) =>
      samples != old.samples ||
      selected != old.selected ||
      colors != old.colors;
}
