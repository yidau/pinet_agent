import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';
import 'dashboard_page.dart';
import 'message_repository.dart';
import 'monitor_focus.dart';
import 'proto/monitoring.pb.dart';
import 'telemetry_connection.dart';

class NormalMonitorPage extends StatefulWidget {
  const NormalMonitorPage({
    super.key,
    required this.connection,
    required this.active,
  });
  final TelemetryConnection connection;
  final bool active;

  @override
  State<NormalMonitorPage> createState() => _NormalMonitorPageState();
}

class _NormalMonitorPageState extends State<NormalMonitorPage> {
  static const _profiles = {
    CaptureProfile.LIGHT: '轻量',
    CaptureProfile.BALANCED: '均衡',
    CaptureProfile.EXTENDED: '扩展',
  };
  final _watch = <String>{};
  final _devices = <ObservedDevice>[];
  final _ssidTraffic = <String, ObservedTraffic>{};
  ObservedDevicesPage? _page;
  String? _boot;
  String? _telemetryEpoch;
  int _lastDeviceRequestSequence = -4;
  String? _notice;
  String? _filter;
  bool _loading = false;
  bool _setting = false;
  bool _closed = false;
  int _loadVersion = 0;
  CaptureProfile? _awaited;

  TelemetryConnection get _connection => widget.connection;

  @override
  void initState() {
    super.initState();
    _connection.snapshotRevision.addListener(_snapshot);
  }

  @override
  void didUpdateWidget(NormalMonitorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active) _snapshot();
      });
    }
  }

  @override
  void dispose() {
    _connection.snapshotRevision.removeListener(_snapshot);
    super.dispose();
  }

  void _snapshot() {
    final snap = _connection.snapshot;
    if (snap == null) return;
    final deviceRebooted = _boot != null &&
        snap.deviceBootId.isNotEmpty &&
        _boot != snap.deviceBootId;
    final telemetryRestarted = _telemetryEpoch != null &&
        _telemetryEpoch != snap.bootId;
    if (deviceRebooted || telemetryRestarted) {
      setState(() {
        // Telemetry process restarts invalidate paging cursors, not this
        // physical monitoring session. Only a Pi reboot clears focus rules.
        if (deviceRebooted) _watch.clear();
        _reset();
      });
    }
    if (snap.deviceBootId.isNotEmpty) _boot = snap.deviceBootId;
    _telemetryEpoch = snap.bootId;
    final pending = _awaited;
    if (pending != null &&
        (snap.capturePolicy.actual == pending.name.toLowerCase() ||
            const {'failed', 'rolled_back'}.contains(snap.capturePolicy.phase))) {
      if (snap.capturePolicy.actual == pending.name.toLowerCase()) {
        setState(_reset);
      } else {
        setState(() => _awaited = null);
      }
    }
    if (!widget.active || _closed || _loading || !_connection.supportsV2 ||
        _connection.phase != TelemetryPhase.live || _connection.stale ||
        _setting || _awaited != null) {
      return;
    }
    final seq = snap.sequence.toInt();
    if (_page == null) {
      if (seq - _lastDeviceRequestSequence >= 2) unawaited(_load());
      return;
    }
    if (shouldReloadObservedDevices(
      visible: widget.active,
      live: _connection.phase == TelemetryPhase.live,
      stale: _connection.stale,
      loading: _loading,
      closed: _closed,
      busy: _setting || _awaited != null || snap.capturePolicy.phase == 'switching',
      pressureFallback: snap.resourcePressure.level == ResourceLevel.LEVEL2_FALLBACK,
      loadedCount: _devices.length,
      currentSequence: seq,
      lastRequestSequence: _lastDeviceRequestSequence,
      latestWirelessSampleMs: snap.wireless.sampledAtMs.toInt(),
      loadedWirelessSampleMs: _page!.sampledAtMs.toInt(),
    )) {
      unawaited(_load());
    }
  }

  void _reset() {
    _loadVersion++;
    _lastDeviceRequestSequence = -4;
    _page = null;
    _loading = false;
    _devices.clear();
    _ssidTraffic.clear();
    _notice = null;
    _awaited = null;
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _connection.stale || !_connection.supportsV2) return;
    final ticket = ++_loadVersion;
    _lastDeviceRequestSequence = _connection.snapshot?.sequence.toInt() ?? _lastDeviceRequestSequence;
    setState(() {
      _loading = true;
      _notice = null;
      _closed = false;
    });
    try {
      final next = await _connection.observedDevices(
        token: more ? _page?.nextPageToken : null,
        ssid: _filter,
      );
      if (!mounted || ticket != _loadVersion) return;
      setState(() {
        if (!more) {
          _devices.clear();
          _ssidTraffic.clear();
        }
        _devices.addAll(next.devices);
        for (final summary in next.ssidTraffic) {
          if (summary.hasTraffic()) _ssidTraffic[summary.ssid] = summary.traffic;
        }
        _page = next;
      });
    } on GrpcError catch (error) {
      if (mounted && ticket == _loadVersion) {
        setState(() {
          _notice = error.code == StatusCode.failedPrecondition
              ? '观测列表已更新，请刷新后继续。'
              : '当前无法读取无线设备。';
        });
      }
    } catch (_) {
      if (mounted && ticket == _loadVersion) {
        setState(() => _notice = '当前无法读取无线设备。');
      }
    } finally {
      if (mounted && ticket == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _profile(CaptureProfile value) async {
    setState(() {
      _setting = true;
      _notice = null;
    });
    try {
      final result = await _connection.setProfile(value);
      if (mounted) {
        setState(() {
          if (result.accepted) {
            _awaited = value;
          } else {
            _notice = result.reason;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _notice = '无法发送采集档位请求。');
    } finally {
      if (mounted) setState(() => _setting = false);
    }
  }

  void _addWatch(String value) {
    if (_watch.contains(value)) return;
    if (_watch.length >= 20) {
      setState(() => _notice = '本次最多关注 20 个 SSID 或 BSSID。');
      return;
    }
    setState(() => _watch.add(value));
  }

  Future<void> _query() async {
    final text = TextEditingController(text: _filter);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('按 SSID 查找'),
        content: TextField(controller: text, maxLength: 32, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    text.dispose();
    if (mounted && value != null) {
      setState(() {
        _filter = value.isEmpty ? null : value;
        _reset();
      });
      await _load();
    }
  }

  Future<void> _background() async {
    final enabled = !_connection.backgroundEnabled;
    final accepted = await _connection.setBackgroundReception(enabled);
    if (mounted && !accepted) {
      setState(() => _notice = '持续接收不可用，请核对连接及 Android 通知权限。');
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: _connection, builder: _body);

  Widget _body(BuildContext context, Widget? child) {
    final snapshot = _connection.snapshot;
    final policy = snapshot?.capturePolicy;
    final selected = _profiles.keys
        .where((value) => value.name.toLowerCase() == policy?.actual)
        .toSet();
    final fallback =
        snapshot?.resourcePressure.level == ResourceLevel.LEVEL2_FALLBACK;
    final interactive =
        _connection.supportsV2 && !_connection.stale && !_closed;
    final observing =
        interactive &&
        !_setting &&
        _awaited == null &&
        policy?.phase != 'switching';
    final trafficAvailable =
        observing &&
        !fallback &&
        _connection.phase == TelemetryPhase.live &&
        const {
          'live_source_window',
          'partial_live_source_window',
        }.contains(snapshot?.wireless.coverage);
    String? trafficLabel(ObservedTraffic? traffic) {
      if (traffic != null && trafficAvailable && policy?.actual == 'light') {
        return '轻量档未采集普通数据帧';
      }
      return observedTrafficLabel(traffic, available: trafficAvailable);
    }

    final aps = <String, List<ObservedDevice>>{};
    final clients = <ObservedDevice>[];
    for (final device in _devices) {
      if (device.kind == ObservedDeviceKind.AP) {
        final key = device.ssid.isEmpty
            ? 'BSSID ${device.bssid}'
            : 'SSID ${device.ssid}';
        (aps[key] ??= []).add(device);
      } else if (device.kind == ObservedDeviceKind.CLIENT) {
        clients.add(device);
      }
    }
    bool watched(ObservedDevice device) =>
        _watch.contains('SSID ${device.ssid}') ||
        _watch.contains('BSSID ${device.bssid}');
    final ssidByBssid = <String, String>{
      for (final group in aps.values)
        for (final ap in group)
          if (ap.ssid.isNotEmpty) ap.bssid: ap.ssid,
    };
    final groups = aps.entries.toList()
      ..sort((a, b) {
        final aWatched = a.value.any(watched);
        final bWatched = b.value.any(watched);
        return aWatched == bWatched ? 0 : (aWatched ? -1 : 1);
      });
    final risk =
        _connection.messages
            .where(
              (message) =>
                  message.event.eventCategory == EventCategory.SECURITY,
            )
            .toList()
          ..sort((a, b) {
            final comparison =
                (focusMatchesBssid(b.event.bssid, _watch, ssidByBssid) ? 1 : 0) -
                (focusMatchesBssid(a.event.bssid, _watch, ssidByBssid) ? 1 : 0);
            return comparison != 0
                ? comparison
                : b.event.timestampMs.compareTo(a.event.timestampMs);
          });
    return ListView(
      key: const PageStorageKey('normal-monitor'),
      padding: const EdgeInsets.all(16),
      children: [
        const ConsoleHeading('当前监控'),
        const SizedBox(height: 8),
        ConsoleCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _closed
                    ? '本次查看已结束'
                    : snapshot?.capture.datasourceState == 'ready' &&
                          interactive
                    ? '监听已就绪'
                    : '待确认采集状态',
              ),
              Text(
                '实际档位 · ${selected.isEmpty ? '未确认' : _profiles[selected.first]}',
              ),
              if (snapshot?.capture.reason.isNotEmpty == true)
                Text(snapshot!.capture.reason),
              if (_awaited != null || policy?.phase == 'switching')
                const Text('正在切换，等待设备回读。'),
              if (policy?.reason.isNotEmpty == true) Text(policy!.reason),
              if (fallback) const Text('资源压力二级，只允许轻量档。'),
              if (!_connection.supportsV2)
                const Text('设备端升级后可查看 V2 无线列表和控制采集。'),
              if (_connection.stale && snapshot != null) const Text('上次快照已过期。'),
              const SizedBox(height: 8),
              SegmentedButton<CaptureProfile>(
                segments: [
                  for (final entry in _profiles.entries)
                    ButtonSegment(
                      value: entry.key,
                      label: Text(entry.value),
                      enabled: !fallback || entry.key == CaptureProfile.LIGHT,
                    ),
                ],
                selected: selected,
                emptySelectionAllowed: true,
                onSelectionChanged: observing
                    ? (value) {
                        if (value.isNotEmpty) unawaited(_profile(value.first));
                      }
                    : null,
              ),
              const SizedBox(height: 6),
              const Text('档位切换可能短暂中断无线观测。'),
            ],
          ),
        ),
        if (_notice case final message?)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(message),
          ),
        const SizedBox(height: 16),
        ConsoleHeading(
          '当前风险',
          trailing: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => _ArchivePage(connection: _connection),
              ),
            ),
            child: const Text('高危档案'),
          ),
        ),
        if (risk.isEmpty) const Text('暂无可显示的安全发现。'),
        for (final item in risk.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shield_outlined),
            title: Text(
              item.event.summary.isNotEmpty
                  ? item.event.summary
                  : item.event.eventType,
            ),
            subtitle: Text(
              item.event.bssid.isEmpty
                  ? item.event.description
                  : item.event.bssid,
            ),
          ),
        if (Platform.isAndroid)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('持续接收告警'),
            subtitle: const Text('依赖与设备热点连接和系统通知权限。'),
            value: _connection.backgroundEnabled,
            onChanged: (value) => unawaited(_background()),
          )
        else
          const Text('持续后台接收适用于 Android。'),
        const SizedBox(height: 14),
        const ConsoleHeading('临时关注'),
        if (_watch.isEmpty) const Text('可从无线列表关注 SSID 或 BSSID。'),
        Wrap(
          spacing: 6,
          children: [
            for (final watch in _watch)
              InputChip(
                label: Text(watch),
                onDeleted: () => setState(() => _watch.remove(watch)),
              ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _closed = false;
                  _watch.clear();
                  _reset();
                });
                unawaited(_load());
              },
              child: const Text('重新开始巡视'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _closed = true;
                _watch.clear();
                _reset();
              }),
              child: const Text('结束本次查看'),
            ),
          ],
        ),
        ConsoleHeading(
          '无线环境',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '按 SSID 查找',
                onPressed: interactive ? _query : null,
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: '刷新观测列表',
                onPressed: interactive && !_loading
                    ? () => unawaited(_load())
                    : null,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_filter case final query?) Text('SSID · $query'),
        if (_page case final page?)
          Text(
            '${_devices.length}/${page.totalCount} 条 · ${formatTelemetryTime(page.sampledAtMs)}'
            '${page.truncated ? ' · 观测范围受限' : ''}${page.coverage == 'resource_fallback' ? ' · 资源回退暂停详情' : ''}',
          ),
        if (_devices.length > 32 &&
            _devices.any((device) => device.hasTraffic()))
          const Text('多页浏览期间保留本次采样，点刷新查看最新流量。'),
        if (_loading) const LinearProgressIndicator(),
        for (final MapEntry(key: groupKey, value: group) in groups)
          ExpansionTile(
            key: PageStorageKey('network-$groupKey'),
            tilePadding: EdgeInsets.zero,
            title: Text(
              group.first.ssid.isEmpty
                  ? '隐藏网络 · ${group.first.bssid}'
                  : group.first.ssid,
            ),
            subtitle: Text([
              '${group.length} 个 BSSID${group.any(watched) ? ' · 已关注' : ''}',
              ?trafficLabel(
                group.first.ssid.isNotEmpty
                    ? _ssidTraffic[group.first.ssid]
                    : group.first.hasTraffic()
                    ? group.first.traffic
                    : null,
              ),
            ].join('\n')),
            children: [
              if (group.first.ssid.isNotEmpty)
                TextButton(
                  onPressed: () => _addWatch('SSID ${group.first.ssid}'),
                  child: const Text('关注此 SSID'),
                ),
              for (final ap in group)
                ExpansionTile(
                  title: Text(ap.bssid),
                  subtitle: Text([
                    [
                      ap.security,
                      if (ap.channel.isNotEmpty) '信道 ${ap.channel}',
                      if (ap.hasRssiDbm()) '${ap.rssiDbm.round()} dBm',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    if (group.first.ssid.isNotEmpty && ap.hasTraffic())
                      ?trafficLabel(ap.traffic),
                  ].where((s) => s.isNotEmpty).join('\n')),
                  children: [
                    Text('来源 · 监听网卡 · ${formatTelemetryTime(ap.lastSeenMs)}'),
                    TextButton(
                      onPressed: () => _addWatch('BSSID ${ap.bssid}'),
                      child: const Text('关注此 BSSID'),
                    ),
                    for (final client in clients.where(
                      (item) => item.relatedApBssid == ap.bssid,
                    ))
                      ListTile(
                        leading: const Icon(Icons.devices_other),
                        title: Text(client.mac),
                        subtitle: Text(
                          '已观测关联 · ${formatTelemetryTime(client.lastSeenMs)}',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        if (clients.any(
          (client) =>
              client.associationState != AssociationState.CONFIRMED ||
              !aps.values.any(
                (group) => group.any((ap) => ap.bssid == client.relatedApBssid),
              ),
        ))
          ExpansionTile(
            title: const Text('关联尚未确认的客户端'),
            children: [
              for (final client in clients.where(
                (item) =>
                    item.associationState != AssociationState.CONFIRMED ||
                    !aps.values.any(
                      (group) =>
                          group.any((ap) => ap.bssid == item.relatedApBssid),
                    ),
              ))
                ListTile(
                  title: Text(client.mac),
                  subtitle: Text(formatTelemetryTime(client.lastSeenMs)),
                ),
            ],
          ),
        if (_page?.nextPageToken.isNotEmpty == true)
          TextButton(
            onPressed: _loading || !interactive
                ? null
                : () => unawaited(_load(more: true)),
            child: const Text('加载下一页'),
          ),
      ],
    );
  }
}

class _ArchivePage extends StatefulWidget {
  const _ArchivePage({required this.connection});
  final TelemetryConnection connection;

  @override
  State<_ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<_ArchivePage> {
  final _rows = <HighRiskRecord>[];
  bool _loading = false;
  bool _more = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) _rows.clear();
    });
    try {
      final page = await widget.connection.highRiskPage(_rows.length);
      if (mounted) {
        setState(() {
          _rows.addAll(page);
          _more = page.length == 30;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '高危档案暂不可读。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(HighRiskRecord record) async {
    final event = record.envelope.event;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('高危发现详情'),
        content: SingleChildScrollView(
          child: Text(
            '${event.eventType}\n${event.description}\n'
            '${event.sourceScope} · ${event.bssid} · ${event.evidenceId}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('删除'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'resolved'),
            child: const Text('标记已处理'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'acknowledged'),
            child: const Text('标记已读'),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除本地档案？'),
          content: const Text('删除后无法从树莓派恢复此档案。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    try {
      await widget.connection.updateHighRisk(
        record.envelope.durableId,
        delete: selected == 'delete',
        status: selected,
      );
      if (mounted) await _load(reset: true);
    } catch (_) {
      if (mounted) setState(() => _error = '无法修改档案，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('高危档案'),
      actions: [
        IconButton(
          tooltip: '刷新档案',
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : () => unawaited(_load(reset: true)),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('手机长期保留已保存档案。树莓派最多等待确认 180 秒，整机重启时丢弃上次开机的未确认记录。'),
        if (_error case final error?) Text(error),
        if (_loading) const LinearProgressIndicator(),
        if (!_loading && _rows.isEmpty && _error == null) const Text('暂无高危档案。'),
        for (final row in _rows)
          ListTile(
            title: Text(
              row.envelope.event.summary.isEmpty
                  ? '疑似高危无线行为'
                  : row.envelope.event.summary,
            ),
            subtitle: Text(
              '${formatTelemetryTime(row.envelope.event.timestampMs)} · '
              '${row.status == 'resolved' ? '已处理' : (row.unread ? '未读' : '已读')}',
            ),
            onTap: () => unawaited(_open(row)),
          ),
        if (_more && _rows.isNotEmpty)
          TextButton(
            onPressed: _loading ? null : () => unawaited(_load()),
            child: const Text('加载下一页'),
          ),
      ],
    ),
  );
}
