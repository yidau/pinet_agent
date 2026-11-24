import 'dart:async';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:material_ui/material_ui.dart';

import '../active_lab/radio_lab_page.dart';
import '../ui/console_style.dart';
import 'dashboard_page.dart';
import 'message_repository.dart';
import 'monitor_focus.dart';
import 'monitoring_widgets.dart';
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
  final _sheetRevision = ValueNotifier(0);
  ObservedDevicesPage? _page;
  String? _boot;
  String? _telemetryEpoch;
  String? _notice;
  int _lastRequest = -4;
  int _loadTicket = 0;
  bool _loading = false;
  bool _setting = false;
  bool _backgroundChanging = false;
  bool _closed = false;
  CaptureProfile? _awaited;
  bool? _awaitedPause;
  Timer? _modeDeadline;

  TelemetryConnection get _connection => widget.connection;
  bool get _online =>
      _connection.phase == TelemetryPhase.live && !_connection.stale;
  bool get _fallback =>
      _connection.snapshot?.resourcePressure.level ==
      ResourceLevel.LEVEL2_FALLBACK;
  bool get _switching =>
      _setting ||
      _connection.applyingDefaultProfile ||
      _awaited != null ||
      _connection.snapshot?.capturePolicy.phase == 'switching';
  String? get _actual => _connection.snapshot?.capturePolicy.actual;
  bool get _paused => _connection.snapshot?.capture.datasourceState == 'paused';
  bool get _pauseRequested =>
      _connection.snapshot?.capture.observationPauseRequested ?? false;
  bool get _canRead =>
      !_closed &&
      _online &&
      _connection.supportsV2 &&
      !_fallback &&
      !_paused &&
      !_pauseRequested &&
      _awaitedPause == null &&
      !_switching;

  bool get _trafficAvailable {
    final snapshot = _connection.snapshot;
    final page = _page;
    return _canRead &&
        page != null &&
        page.hasSampledAtMs() &&
        page.sampledAtMs.toInt() > 0 &&
        (snapshot!.timestampMs.toInt() - page.sampledAtMs.toInt()).abs() <=
            20000 &&
        const {
          'live_source_window',
          'partial_live_source_window',
        }.contains(snapshot.wireless.coverage);
  }

  Iterable<ObservedDevice> get _accessPoints =>
      _page?.devices.where((item) => item.kind == ObservedDeviceKind.AP) ??
      const [];
  Iterable<ObservedDevice> get _clients =>
      _page?.devices.where((item) => item.kind == ObservedDeviceKind.CLIENT) ??
      const [];

  @override
  void initState() {
    super.initState();
    _connection.snapshotRevision.addListener(_snapshot);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active) _snapshot();
    });
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
    _modeDeadline?.cancel();
    _sheetRevision.dispose();
    super.dispose();
  }

  void _update(VoidCallback update) {
    setState(update);
    _sheetRevision.value++;
  }

  void _restartList() {
    _loadTicket++;
    _lastRequest = -4;
    _loading = false;
    _page = null;
    _notice = null;
    _awaited = null;
  }

  void _snapshot() {
    final snap = _connection.snapshot;
    if (snap == null) return;
    final rebooted =
        _boot != null &&
        snap.deviceBootId.isNotEmpty &&
        _boot != snap.deviceBootId;
    final restarted = _telemetryEpoch != null && _telemetryEpoch != snap.bootId;
    if (rebooted || restarted) {
      _update(() {
        if (rebooted) _watch.clear();
        _restartList();
      });
    }
    if (snap.deviceBootId.isNotEmpty) _boot = snap.deviceBootId;
    _telemetryEpoch = snap.bootId;
    if (_awaitedPause case final awaiting?) {
      final state = snap.capture.datasourceState;
      if ((awaiting && state == 'paused') ||
          (!awaiting && state == 'ready' && !_pauseRequested)) {
        _modeDeadline?.cancel();
        _update(() {
          _awaitedPause = null;
          _lastRequest = -4;
        });
      }
    }
    if (_awaited case final pending?) {
      if (snap.capturePolicy.actual == pending.name.toLowerCase()) {
        _update(_restartList);
      } else if (const {
        'failed',
        'rolled_back',
      }.contains(snap.capturePolicy.phase)) {
        _update(() {
          _awaited = null;
          _notice = snap.capturePolicy.reason;
        });
      }
    }
    if (!widget.active || !_canRead || _loading) return;
    final sequence = snap.sequence.toInt();
    if (_page == null) {
      if (sequence - _lastRequest >= 2) unawaited(_load());
    } else if (shouldReloadObservedDevices(
      visible: widget.active,
      live: _online,
      stale: _connection.stale,
      loading: _loading,
      closed: _closed,
      busy: _switching,
      pressureFallback: _fallback,
      currentSequence: sequence,
      lastRequestSequence: _lastRequest,
      latestWirelessSampleMs: snap.wireless.sampledAtMs.toInt(),
      loadedWirelessSampleMs: _page!.sampledAtMs.toInt(),
    )) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading || !_canRead) return;
    final ticket = ++_loadTicket;
    bool current() => mounted && ticket == _loadTicket;
    _lastRequest = _connection.snapshot?.sequence.toInt() ?? _lastRequest;
    _update(() {
      _loading = true;
      _notice = null;
    });
    try {
      final page = await readObservedSnapshot(
        (token) => _connection.observedDevices(token: token),
        isCurrent: () => current() && _canRead,
      );
      if (current() && page != null) _update(() => _page = page);
    } on GrpcError catch (error) {
      if (current()) {
        _update(
          () => _notice = error.code == StatusCode.failedPrecondition
              ? '观测列表已更新，请刷新重试。'
              : '当前无法读取无线设备。',
        );
      }
    } catch (_) {
      if (current()) _update(() => _notice = '当前无法读取无线设备。');
    } finally {
      if (current()) _update(() => _loading = false);
    }
  }

  Future<void> _setPause(bool paused) async {
    _update(() {
      _awaitedPause = paused;
      _notice = null;
    });
    _modeDeadline?.cancel();
    _modeDeadline = Timer(const Duration(seconds: 25), () {
      _update(() {
        _awaitedPause = null;
        _notice = '设备尚未确认切换，请查看监听状态。';
      });
    });
    var error = '';
    try {
      final result = await _connection.setObservationPaused(paused);
      if (!result.accepted) {
        error = result.status == CommandStatus.BUSY
            ? '外接网卡正在处理其他操作，请稍后重试。'
            : '树莓派拒绝了模式切换。';
      }
    } catch (_) {
      error = '暂时无法确认请求，请查看后续监听状态。';
    }
    if (!mounted || _awaitedPause != paused || error.isEmpty) return;
    _modeDeadline?.cancel();
    _update(() {
      _awaitedPause = null;
      _notice = error;
    });
  }

  Future<void> _setProfile(CaptureProfile profile) async {
    if (_switching ||
        !_online ||
        !_connection.supportsV2 ||
        _closed ||
        _actual == profile.name.toLowerCase() ||
        (_fallback && profile != CaptureProfile.LIGHT)) {
      return;
    }
    _update(() {
      _setting = true;
      _notice = null;
    });
    try {
      final response = await _connection.setProfile(profile);
      if (mounted) {
        _update(() {
          if (response.accepted) {
            _awaited = profile;
          } else {
            _notice = response.reason;
          }
        });
      }
    } catch (_) {
      if (mounted) _update(() => _notice = '无法发送采集档位请求。');
    } finally {
      if (mounted) {
        _update(() => _setting = false);
        _snapshot();
      }
    }
  }

  Future<void> _setBackground(bool enabled) async {
    if (_backgroundChanging) return;
    _update(() => _backgroundChanging = true);
    try {
      if (!await _connection.setBackgroundReception(enabled) && mounted) {
        _update(() => _notice = '持续接收不可用，请核对连接与 Android 通知权限。');
      }
    } catch (_) {
      if (mounted) _update(() => _notice = '无法更新持续接收设置。');
    } finally {
      if (mounted) _update(() => _backgroundChanging = false);
    }
  }

  void _toggleWatch(String value) => _update(() {
    if (_watch.remove(value)) return;
    if (_watch.length >= 20) {
      _notice = '本次最多关注 20 个 SSID 或 BSSID。';
    } else {
      _watch.add(value);
      _notice = null;
    }
  });

  bool _watched(ObservedDevice ap) =>
      _watch.contains('BSSID ${ap.bssid}') ||
      _watch.contains('SSID ${ap.ssid}');

  List<ObservedDevice> get _activePoints {
    if (!_trafficAvailable || _actual == 'light') return [];
    return _accessPoints.where(hasRecentObservedTraffic).toList()..sort((a, b) {
      final dbm = (b.hasRssiDbm() ? b.rssiDbm : -161).compareTo(
        a.hasRssiDbm() ? a.rssiDbm : -161,
      );
      if (dbm != 0) return dbm;
      final recent = b.lastSeenMs.compareTo(a.lastSeenMs);
      return recent != 0 ? recent : a.bssid.compareTo(b.bssid);
    });
  }

  List<_Network> _groups(Iterable<ObservedDevice> points) {
    final groups = <String, List<ObservedDevice>>{};
    final summaries = <String, ObservedTraffic>{
      for (final entry in _page?.ssidTraffic ?? const <SsidTraffic>[])
        if (entry.hasTraffic()) entry.ssid: entry.traffic,
    };
    for (final ap in points) {
      (groups[ap.ssid.isEmpty ? 'BSSID ${ap.bssid}' : 'SSID ${ap.ssid}'] ??= [])
          .add(ap);
    }
    final networks = [
      for (final entry in groups.entries)
        _Network(
          entry.key,
          entry.value,
          entry.value.first.ssid.isEmpty
              ? _traffic(entry.value.first)
              : _trafficText(summaries[entry.value.first.ssid]),
          entry.value.any(_watched),
        ),
    ];
    return [
      ...networks.where((network) => network.watched),
      ...networks.where((network) => !network.watched),
    ];
  }

  String? _traffic(ObservedDevice ap) =>
      _trafficText(ap.hasTraffic() ? ap.traffic : null);

  String? _trafficText(ObservedTraffic? traffic) {
    if (traffic != null && _trafficAvailable && _actual == 'light') {
      return '轻量档未采集普通数据帧';
    }
    return observedTrafficLabel(traffic, available: _trafficAvailable);
  }

  String _emptySummary() {
    if (_closed) return '本次查看已结束。';
    if (!_online) return '等待树莓派实时连接。';
    if (!_connection.supportsV2) return '设备端升级后可查看无线设备。';
    if (_paused) return '监听已暂停。可在「查看所有」查看上次观测。';
    if (_awaitedPause != null || _pauseRequested) return '等待树莓派确认监听状态。';
    if (_switching) return '正在切换档位，等待采样。';
    if (_fallback) return '资源压力较高，设备暂停无线详情。';
    if (_actual == 'light') return '轻量档未采集流量，可查看所有 AP。';
    if (_loading && _page == null) return '正在读取无线观测。';
    if (!_trafficAvailable) return '等待有效的无线观测样本。';
    if (_accessPoints.any(
      (ap) => ap.traffic.status == TrafficStatus.TRAFFIC_WARMING_UP,
    )) {
      return '等待完整的 30 秒流量采样。';
    }
    if (_accessPoints.isNotEmpty &&
        !_accessPoints.any((ap) => ap.traffic.hasObservedBytes())) {
      return '暂无流量样本，可查看所有 AP。';
    }
    return '最近 30 秒未观测到流量。';
  }

  void _showLive(BuildContext context, WidgetBuilder builder) {
    showMonitoringSheet(
      context,
      (_) => ListenableBuilder(
        listenable: Listenable.merge([_connection, _sheetRevision]),
        builder: (context, _) => builder(context),
      ),
    );
  }

  void _showSettings(BuildContext context) => _showLive(
    context,
    (_) => MonitoringSheetBody(
      '监控设置',
      children: [
        if (_switching) const Text('正在切换，等待设备确认。'),
        if (_fallback) const Text('资源压力较高，当前只可使用轻量档。'),
        if (_notice case final notice? when notice.isNotEmpty) Text(notice),
        Text('实际档位 · ${captureProfileLabel(_actual)}'),
        const SizedBox(height: 8),
        SegmentedButton<CaptureProfile>(
          segments: [
            for (final entry in _profiles.entries)
              ButtonSegment(
                value: entry.key,
                label: Text(entry.value),
                enabled: !_fallback || entry.key == CaptureProfile.LIGHT,
              ),
          ],
          selected: _profiles.keys
              .where((profile) => profile.name.toLowerCase() == _actual)
              .toSet(),
          emptySelectionAllowed: true,
          onSelectionChanged:
              _online &&
                  _connection.supportsV2 &&
                  !_closed &&
                  !_switching &&
                  !_paused &&
                  !_pauseRequested &&
                  _awaitedPause == null
              ? (selection) {
                  if (selection.isNotEmpty) {
                    unawaited(_setProfile(selection.first));
                  }
                }
              : null,
        ),
        const SizedBox(height: 6),
        const Text('切换档位时，新的 30 秒流量窗口会重新累计。'),
        if (Platform.isAndroid)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('持续接收告警'),
            subtitle: const Text('需要设备热点连接和 Android 通知权限。'),
            value: _connection.backgroundEnabled,
            onChanged: _backgroundChanging
                ? null
                : (value) => unawaited(_setBackground(value)),
          )
        else
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('持续接收告警适用于 Android。'),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _setClosed(false),
              child: const Text('重新开始巡视'),
            ),
            TextButton(
              onPressed: _closed ? null : () => _setClosed(true),
              child: const Text('结束本次查看'),
            ),
          ],
        ),
      ],
    ),
  );

  void _setClosed(bool closed) {
    _update(() {
      _closed = closed;
      _watch.clear();
      _restartList();
    });
    if (!closed) unawaited(_load());
  }

  void _showWatch(BuildContext context) => _showLive(
    context,
    (_) => MonitoringSheetBody(
      '临时关注',
      children: [
        if (_watch.isEmpty) const Text('可以在 SSID 或接入点详情中添加关注。'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final target in _watch)
              InputChip(
                label: Text(target),
                onDeleted: () => _toggleWatch(target),
              ),
          ],
        ),
      ],
    ),
  );

  void _showRisks(BuildContext context) => _showLive(context, (sheetContext) {
    final ssids = {for (final ap in _accessPoints) ap.bssid: ap.ssid};
    final events =
        _connection.messages
            .where(
              (message) =>
                  message.event.eventCategory == EventCategory.SECURITY,
            )
            .toList()
          ..sort((a, b) {
            final focus =
                (focusMatchesBssid(b.event.bssid, _watch, ssids) ? 1 : 0) -
                (focusMatchesBssid(a.event.bssid, _watch, ssids) ? 1 : 0);
            return focus == 0
                ? b.event.timestampMs.compareTo(a.event.timestampMs)
                : focus;
          });
    return MonitoringSheetBody(
      '当前风险',
      children: [
        if (events.isEmpty) const Text('暂无可显示的安全发现。'),
        for (final entry in events.take(5))
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            contentPadding: EdgeInsets.zero,
            title: Text(
              entry.event.summary.isNotEmpty
                  ? entry.event.summary
                  : entry.event.eventType,
            ),
            subtitle: Text(
              entry.event.bssid.isNotEmpty
                  ? entry.event.bssid
                  : entry.event.description,
            ),
          ),
        OutlinedButton(
          onPressed: () => Navigator.push<void>(
            sheetContext,
            MaterialPageRoute(
              builder: (_) => _ArchivePage(connection: _connection),
            ),
          ),
          child: const Text('高危档案'),
        ),
      ],
    );
  });

  void _showAccessPoint(BuildContext context, ObservedDevice selected) =>
      _showLive(context, (_) {
        final current = _accessPoints
            .where((ap) => ap.bssid == selected.bssid)
            .firstOrNull;
        final ap = current ?? selected;
        final clients = _clients.where(
          (client) =>
              client.associationState == AssociationState.CONFIRMED &&
              client.relatedApBssid == ap.bssid,
        );
        final bssid = 'BSSID ${ap.bssid}';
        final ssid = 'SSID ${ap.ssid}';
        return MonitoringSheetBody(
          '接入点详情',
          children: [
            Text(ap.bssid, style: Theme.of(context).textTheme.headlineSmall),
            Text('所属网络 · ${ap.ssid.isEmpty ? '隐藏网络' : ap.ssid}'),
            const SizedBox(height: 8),
            _fact('信号', _signal(ap)),
            _fact('信道', ap.channel.isEmpty ? '未报告' : ap.channel),
            _fact('加密', ap.security.isEmpty ? '未报告' : ap.security),
            _fact(
              '观测流量',
              (current == null ? null : _traffic(ap)) ?? '暂无有效流量样本',
            ),
            _fact('最近观测', formatTelemetryTime(ap.lastSeenMs)),
            _fact('来源', '监听网卡'),
            _fact('已观测关联客户端', '${clients.length}'),
            for (final client in clients)
              _fact(client.mac, formatTelemetryTime(client.lastSeenMs)),
            if (_notice case final notice? when notice.isNotEmpty) Text(notice),
            if (ap.ssid.isNotEmpty && _connection.supportsRadioLab)
              FilledButton.icon(
                icon: const Icon(Icons.shield_outlined),
                label: const Text('查看授权无线安全验证'),
                onPressed: _closed || !_online || _paused || _pauseRequested
                    ? null
                    : () => unawaited(Navigator.of(context).push<void>(
                          MaterialPageRoute(builder: (_) => RadioLabPage(
                            connection: _connection,
                            bssid: ap.bssid,
                            ssid: ap.ssid,
                            channel: ap.channel,
                          )),
                        )),
              ),
            OutlinedButton(
              onPressed: _closed ? null : () => _toggleWatch(bssid),
              child: Text(_watch.contains(bssid) ? '取消关注此 BSSID' : '关注此 BSSID'),
            ),
            if (ap.ssid.isNotEmpty)
              TextButton(
                onPressed: _closed ? null : () => _toggleWatch(ssid),
                child: Text(_watch.contains(ssid) ? '取消关注此 SSID' : '关注此 SSID'),
              ),
          ],
        );
      });

  void _showPriority(BuildContext context) =>
      _showLive(context, (sheetContext) {
        final priority = _activePoints.take(8).toList();
        return MonitoringSheetBody(
          '重点接入点',
          children: [
            if (priority.isEmpty) Text(_emptySummary()),
            for (final ap in priority)
              _PointRow(
                ap,
                title: ap.ssid.isEmpty ? '隐藏网络' : ap.ssid,
                onTap: () => _showAccessPoint(sheetContext, ap),
              ),
          ],
        );
      });

  void _showAll(BuildContext context, {String search = ''}) {
    if (_page == null) unawaited(_load());
    showMonitoringSheet(context, (_) {
      var query = search;
      return StatefulBuilder(
        builder: (context, setSearch) => ListenableBuilder(
          listenable: Listenable.merge([_connection, _sheetRevision]),
          builder: (context, _) {
            final observed = _accessPoints.toList();
            final term = query.trim().toLowerCase();
            final groups = <_Network>[];
            for (final network in _groups(observed)) {
              if (network.name.toLowerCase().contains(term)) {
                groups.add(network);
              } else {
                final matches = network.points
                    .where((ap) => ap.bssid.toLowerCase().contains(term))
                    .toList();
                if (matches.isNotEmpty) {
                  groups.add(
                    _Network(network.key, matches, null, network.watched),
                  );
                }
              }
            }
            final bssids = observed.map((ap) => ap.bssid).toSet();
            final unresolved = _clients
                .where(
                  (client) =>
                      client.associationState != AssociationState.CONFIRMED ||
                      !bssids.contains(client.relatedApBssid),
                )
                .toList();
            final page = _page;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConsoleHeading(
                    '所有接入点',
                    trailing: IconButton(
                      tooltip: '刷新无线观测',
                      onPressed: _canRead && !_loading ? _load : null,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  TextFormField(
                    initialValue: search,
                    decoration: const InputDecoration(
                      hintText: '搜索 SSID 或 BSSID',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (value) => setSearch(() => query = value),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '已观测 ${observed.length} 个 AP${page?.truncated == true ? ' · 观测范围受限' : ''}'
                    '${page?.hasSampledAtMs() == true ? ' · ${formatTelemetryTime(page!.sampledAtMs, includeDate: false)}' : ''}',
                  ),
                  if (_loading && page == null) const LinearProgressIndicator(),
                  if (_notice case final notice? when notice.isNotEmpty)
                    Text(notice),
                  Expanded(
                    child:
                        groups.isEmpty &&
                            (term.isNotEmpty || unresolved.isEmpty)
                        ? Center(
                            child: Text(
                              term.isNotEmpty ? '没有匹配的接入点' : '暂无接入点观测',
                            ),
                          )
                        : ListView.builder(
                            itemCount:
                                groups.length +
                                (term.isEmpty && unresolved.isNotEmpty ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == groups.length) {
                                return ExpansionTile(
                                  title: Text(
                                    '关联尚未确认的客户端（${unresolved.length}）',
                                  ),
                                  children: [
                                    for (final client in unresolved)
                                      _fact(
                                        client.mac,
                                        formatTelemetryTime(client.lastSeenMs),
                                      ),
                                  ],
                                );
                              }
                              final group = groups[index];
                              return _NetworkTree(
                                key: ValueKey(group.key),
                                network: group,
                                scope: 'all',
                                expanded: true,
                                onOpen: (ap) => _showAccessPoint(context, ap),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }, heightFraction: .90);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _connection,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 610;
        final points = _activePoints;
        final priorityLimit = compact ? 1 : 2;
        final groups = _groups(points);
        final visible = groups.take(compact ? 2 : 3).toList();
        final profile = captureProfileLabel(_actual);
        final background = Platform.isAndroid
            ? ' · 持续接收${_connection.backgroundEnabled ? '开启' : '关闭'}'
            : '';
        final time = _page?.hasSampledAtMs() == true
            ? formatTelemetryTime(_page!.sampledAtMs, includeDate: false)
            : null;
        return ListView(
          key: const PageStorageKey('normal-monitor'),
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          children: [
            const ConsoleHeading('常态监控'),
            const SizedBox(height: 8),
            if (_connection.supportsObservationMode)
              ConsoleCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(
                    _paused ? Icons.pause_circle_outline : Icons.sensors,
                  ),
                  title: Text(_paused ? '监听已暂停' : '常态监听'),
                  subtitle: Text(
                    _awaitedPause != null || (_pauseRequested && !_paused)
                        ? '等待树莓派确认'
                        : _paused && time != null
                        ? '上次观测 · $time'
                        : '外接监听网卡',
                  ),
                  trailing: OutlinedButton(
                    onPressed: _online && !_switching && _awaitedPause == null
                        ? () => unawaited(
                            _setPause(!(_paused || _pauseRequested)),
                          )
                        : null,
                    child: Text(_paused || _pauseRequested ? '恢复监听' : '暂停监听'),
                  ),
                ),
              ),
            ConsoleCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.settings_outlined, size: 20),
                visualDensity: VisualDensity.compact,
                title: const Text('监控设置'),
                subtitle: Text(
                  _switching ? '正在切换 · $profile' : '$profile$background',
                ),
                trailing: const Icon(Icons.expand_more),
                onTap: () => _showSettings(context),
              ),
            ),
            if (_notice case final notice? when notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(notice),
              ),
            if (points.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '重点接入点',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (points.length > priorityLimit)
                    TextButton(
                      onPressed: () => _showPriority(context),
                      child: const Text('更多重点'),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              ConsoleCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (index, ap)
                        in points.take(priorityLimit).indexed) ...[
                      if (index > 0) const Divider(),
                      _PointRow(
                        ap,
                        title: ap.ssid.isEmpty ? '隐藏网络' : ap.ssid,
                        onTap: () => _showAccessPoint(context, ap),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            ConsoleHeading(
              '无线环境',
              trailing: TextButton.icon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text('查看所有'),
                onPressed: () => _showAll(context),
              ),
            ),
            if (visible.isEmpty)
              ConsoleCard(child: Text(_emptySummary()))
            else
              for (final (index, network) in visible.indexed)
                _NetworkTree(
                  key: ValueKey(network.key),
                  network: network,
                  scope: 'preview',
                  expanded: index == 0,
                  childLimit: compact ? 1 : 2,
                  activeOnly: true,
                  onOpen: (ap) => _showAccessPoint(context, ap),
                  onMore: () => _showAll(
                    context,
                    search: network.points.first.ssid.isEmpty
                        ? network.points.first.bssid
                        : network.points.first.ssid,
                  ),
                ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${points.length} 个活跃 BSSID${time == null ? '' : ' · 采样 $time'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: '刷新无线观测',
                  visualDensity: VisualDensity.compact,
                  onPressed: _canRead && !_loading ? _load : null,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _showRisks(context),
                  icon: const Icon(Icons.shield_outlined, size: 17),
                  label: const Text('当前风险'),
                ),
                TextButton.icon(
                  onPressed: () => _showWatch(context),
                  icon: const Icon(Icons.bookmark_border, size: 17),
                  label: Text(
                    _watch.isEmpty ? '临时关注' : '临时关注 ${_watch.length}',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _Network {
  const _Network(this.key, this.points, this.traffic, this.watched);
  final String key;
  final List<ObservedDevice> points;
  final String? traffic;
  final bool watched;

  String get name => points.first.ssid.isEmpty ? '隐藏网络' : points.first.ssid;
}

class _NetworkTree extends StatelessWidget {
  const _NetworkTree({
    super.key,
    required this.network,
    required this.scope,
    required this.expanded,
    required this.onOpen,
    this.childLimit,
    this.onMore,
    this.activeOnly = false,
  });

  final _Network network;
  final String scope;
  final bool expanded;
  final bool activeOnly;
  final int? childLimit;
  final VoidCallback? onMore;
  final ValueChanged<ObservedDevice> onOpen;

  @override
  Widget build(BuildContext context) {
    final points = network.points;
    final visible = points.take(childLimit ?? points.length).toList();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ConsoleCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          key: PageStorageKey('$scope-network-${network.key}'),
          initiallyExpanded: expanded,
          maintainState: false,
          minTileHeight: 47,
          visualDensity: VisualDensity.compact,
          tilePadding: const EdgeInsets.symmetric(horizontal: 11),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
          shape: const Border(),
          collapsedShape: const Border(),
          leading: Icon(Icons.wifi, color: colors.primary, size: 21),
          title: Text(
            network.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            [
              '${points.length} 个${activeOnly ? '活跃 ' : ' '}BSSID',
              ?network.traffic,
              if (network.watched) '已关注',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          children: [
            for (final (index, ap) in visible.indexed)
              Stack(
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    width: 19,
                    child: CustomPaint(
                      painter: _Branch(
                        colors.primary.withValues(alpha: 0.75),
                        index == visible.length - 1,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: _PointRow(
                      ap,
                      title: ap.bssid,
                      showChannel: true,
                      onTap: () => onOpen(ap),
                    ),
                  ),
                ],
              ),
            if (visible.length < points.length && onMore != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onMore,
                  child: Text('查看其余 ${points.length - visible.length} 个 BSSID'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Branch extends CustomPainter {
  const _Branch(this.color, this.last);
  final Color color;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final mid = size.height / 2;
    canvas.drawLine(
      const Offset(4, 0),
      Offset(4, last ? mid : size.height),
      paint,
    );
    canvas.drawLine(Offset(4, mid), Offset(size.width - 2, mid), paint);
  }

  @override
  bool shouldRepaint(_Branch oldDelegate) =>
      oldDelegate.color != color || oldDelegate.last != last;
}

class _PointRow extends StatelessWidget {
  const _PointRow(
    this.ap, {
    required this.title,
    required this.onTap,
    this.showChannel = false,
  });
  final ObservedDevice ap;
  final String title;
  final VoidCallback onTap;
  final bool showChannel;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(
              showChannel ? Icons.router_outlined : Icons.wifi,
              color: Theme.of(context).colorScheme.primary,
              size: 17,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  if (showChannel && ap.channel.isNotEmpty)
                    Text(
                      '信道 ${ap.channel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(_signal(ap), style: Theme.of(context).textTheme.bodySmall),
            const Icon(Icons.chevron_right, size: 15),
          ],
        ),
      ),
    ),
  );
}

String _signal(ObservedDevice ap) =>
    ap.hasRssiDbm() ? '${ap.rssiDbm.round()} dBm' : '信号未报告';

Widget _fact(String title, String value) => ListTile(
  visualDensity: VisualDensity.compact,
  contentPadding: EdgeInsets.zero,
  title: Text(title),
  subtitle: Text(value),
);

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
