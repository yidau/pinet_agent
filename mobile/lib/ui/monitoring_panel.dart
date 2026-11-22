import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../mcp/operator_client.dart';
import '../mcp/tool_registry.dart';
import '../network.dart';
import 'console_style.dart';
import 'workspace_data.dart';

class MonitoringPanel extends StatefulWidget {
  const MonitoringPanel({super.key, required this.session});
  final DeviceSession session;

  @override
  State<MonitoringPanel> createState() => _MonitoringPanelState();
}

class _MonitoringPanelState extends State<MonitoringPanel>
    with AutomaticKeepAliveClientMixin {
  Json? _status;
  String? _error;
  Timer? _poll;
  bool _visible = false;
  int _epoch = 0;
  int? _readingEpoch;
  bool _commanding = false;
  final _age = Stopwatch();
  bool get _active => const {'running', 'stopping'}.contains(_status?['state']);
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible == visible) return;
    _visible = visible;
    _poll?.cancel();
    if (visible &&
        (_status == null || _active || _age.elapsed.inSeconds >= 15)) {
      unawaited(_read());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _schedule() {
    _poll?.cancel();
    if (_visible && _active && !_commanding && widget.session.isActive) {
      _poll = Timer(const Duration(seconds: 4), _read);
    }
  }

  Future<void> _read({bool refreshCapabilities = false}) async {
    final session = widget.session;
    final epoch = _epoch;
    if (_readingEpoch == epoch ||
        _commanding ||
        !session.isActive ||
        session.registry['get_wireless_monitoring_status']?.isCallable !=
            true) {
      return;
    }
    _readingEpoch = epoch;
    try {
      final reply = await session.callTool(
        'get_wireless_monitoring_status',
        {},
      );
      if (!mounted || !session.isActive || epoch != _epoch) return;
      if (reply['ok'] == false) {
        throw FormatException(displayText(reply['message']) ?? '读取观测状态失败。');
      }
      final status = reply['data'] is Json ? reply['data'] as Json : reply;
      if (status['state'] is! String) throw const FormatException('设备未报告观测状态。');
      final hasSample =
          status['scan_count'] is int && (status['scan_count'] as int) > 0;
      final changed =
          hasSample &&
          (status['session_id'] != _status?['session_id'] ||
              status['scan_count'] != _status?['scan_count']);
      final stateChanged =
          _status != null && status['state'] != _status?['state'];
      setState(() {
        _status = status;
        _error = null;
      });
      _age
        ..reset()
        ..start();
      if ((changed || stateChanged || refreshCapabilities) && _visible) {
        await session.refreshCapabilities();
      }
    } on FormatException catch (e) {
      if (mounted && session.isActive && epoch == _epoch) {
        setState(() => _error = e.message);
      }
    } finally {
      if (_readingEpoch == epoch) {
        _readingEpoch = null;
        if (mounted && epoch == _epoch) _schedule();
      }
    }
  }

  Future<void> _confirm(bool start) async {
    final session = widget.session;
    final id = _status?['session_id'];
    final args = await showDialog<Json>(
      context: context,
      builder: (dialog) => start
          ? const _StartDialog()
          : AlertDialog(
              title: const Text('结束本次观测？'),
              content: const Text('结束后可以查看本次观测的变化摘要。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialog, <String, dynamic>{'confirm': true}),
                  child: const Text('确认停止'),
                ),
              ],
            ),
    );
    if (args == null || !mounted || !session.isActive || _commanding) return;
    if (start == _active || (!start && id != _status?['session_id'])) return;
    _poll?.cancel();
    setState(() {
      _epoch++;
      _commanding = true;
      _error = null;
    });
    String? failure;
    try {
      await session.operatorClient.call(
        start ? PhoneAction.monitoringStart : PhoneAction.monitoringStop,
        args,
      );
    } on FormatException catch (e) {
      failure = e.message;
    } finally {
      if (mounted && session.isActive) {
        setState(() => _commanding = false);
        await _read(refreshCapabilities: true);
        if (mounted && failure != null) setState(() => _error = failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final registry = widget.session.registry;
    final state = _status?['state'];
    final startTool = registry['start_wireless_monitoring'];
    final control = _active ? registry['stop_wireless_monitoring'] : startTool;
    final permitted =
        registry.phoneControl && control?.status == CapabilityStatus.available;
    final disabled = !registry.phoneControl
        ? '使用已注册手机连接后可控制观测。'
        : control?.reason;
    final reason =
        displayText(_status?['reason']) ??
        (!permitted ? displayText(disabled) : null);
    final degraded =
        state == 'degraded' ||
        (state == 'idle' && startTool?.status == CapabilityStatus.degraded);
    final label = degraded
        ? '条件不足'
        : switch (state) {
            'idle' => '待开始',
            'running' => '进行中',
            'stopping' => '正在停止',
            'stopped' => '已停止',
            'completed' => '已完成',
            _ => _error == null ? '读取中' : '状态未知',
          };
    final elapsed = _status?['elapsed_seconds'];
    final duration = elapsed is num && elapsed.isFinite && elapsed >= 0
        ? Duration(seconds: elapsed.floor())
        : null;
    final summary = _status?['summary'];
    final events = _status?['recent_events'];
    final finished =
        state == 'completed' || state == 'stopped' || state == 'degraded';
    final hasSession = _status?['session_id'] != null;
    final technicalSource = _status?['observation_source'];
    return ConsoleCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(degraded ? Icons.info_outline : Icons.timeline, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '持续观测',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              IconButton(
                tooltip: '刷新观测状态',
                onPressed: _commanding
                    ? null
                    : () => _read(refreshCapabilities: true),
                icon: const Icon(Icons.refresh, size: 19),
              ),
            ],
          ),
          if (hasSession && duration != null)
            Text(
              '已运行 ${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
            ),
          if (technicalSource != null)
            Text('数据来源 · ${sourceName(technicalSource)}'),
          if (hasSession)
            Text(
              [
                if (_status?['scan_count'] case final int n) '已观测 $n 次',
                if (_status?['ap_count'] case final int n) '发现 $n 个接入点',
                if (_status?['new_ap_count'] case final int n) '新增 $n 个',
              ].join(' · '),
            ),
          if (finished && hasSession && summary is Json) ...[
            const SizedBox(height: 6),
            Text('变化摘要', style: Theme.of(context).textTheme.labelLarge),
            if (_status?['scan_count'] == 0)
              const Text('本次没有完成采样，无法比较无线环境的变化。')
            else
              Text(
                [
                  if (summary['baseline_ap_count'] case final int n)
                    '首次观测 $n 个接入点',
                  if (summary['channel_change_count'] case final int n)
                    '$n 次信道变化',
                  if (summary['security_change_count'] case final int n)
                    '$n 次安全配置变化',
                ].join(' · '),
              ),
            if (summary['truncated'] == true) const Text('部分观测受数据源或保留条数限制。'),
          ],
          if (events is List && events.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('近期变化'),
              children: [
                for (final event
                    in events.whereType<Json>().toList()..sort(
                      (a, b) =>
                          (deviceTime(b['timestamp'])?.millisecondsSinceEpoch ??
                                  0)
                              .compareTo(
                                deviceTime(a['timestamp'])
                                        ?.millisecondsSinceEpoch ??
                                    0,
                              ),
                    ))
                  _Change(event: event),
              ],
            ),
          if (reason != null) Text(reason),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 4),
          if (control != null)
            FilledButton.tonalIcon(
              onPressed:
                  !permitted ||
                      state == null ||
                      _commanding ||
                      state == 'stopping'
                  ? null
                  : () => _confirm(!_active),
              icon: Icon(_active ? Icons.stop : Icons.play_arrow),
              label: Text(_active ? '停止观测' : '开始观测'),
            ),
        ],
      ),
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.event});
  final Json event;
  @override
  Widget build(BuildContext context) {
    final kind = switch (event['type']) {
      'new_ap' => '新接入点',
      'channel_change' => '信道变化',
      'security_change' => '安全配置变化',
      _ => '无线变化',
    };
    final time = deviceTime(event['timestamp']);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.timeline),
      title: Text(
        '$kind · ${displayText(event['ssid']) ?? displayText(event['bssid']) ?? '名称未报告'}',
      ),
      subtitle: Text(
        [
          if (event['previous'] != null && event['current'] != null)
            "${event['previous']} → ${event['current']}",
          if (time != null) displayTime(time),
        ].join(' · '),
      ),
    );
  }
}

class _StartDialog extends StatefulWidget {
  const _StartDialog();
  @override
  State<_StartDialog> createState() => _StartDialogState();
}

class _StartDialogState extends State<_StartDialog> {
  int minutes = 10, seconds = 30;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('开始持续观测？'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('树莓派会按间隔读取已开启的监听源；需要普通扫描时，仅使用与管理热点独立的无线电。离开页面后观测仍会继续。'),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: minutes,
            decoration: const InputDecoration(labelText: '持续时间'),
            items: [
              for (final n in [5, 10, 30, 60])
                DropdownMenuItem(value: n, child: Text('$n 分钟')),
            ],
            onChanged: (n) {
              if (n != null) setState(() => minutes = n);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: seconds,
            decoration: const InputDecoration(labelText: '观测间隔'),
            items: [
              for (final n in [30, 60, 120])
                DropdownMenuItem(value: n, child: Text('$n 秒')),
            ],
            onChanged: (n) {
              if (n != null) setState(() => seconds = n);
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, <String, dynamic>{
          'confirm': true,
          'duration_seconds': minutes * 60,
          'interval_seconds': seconds,
        }),
        child: const Text('确认开始'),
      ),
    ],
  );
}
