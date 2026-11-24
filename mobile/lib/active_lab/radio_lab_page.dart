import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../telemetry/proto/monitoring.pb.dart';
import '../telemetry/telemetry_connection.dart';

/// Only pre-provisioned isolated lab targets can be used.
class RadioLabPage extends StatefulWidget {
  const RadioLabPage({
    super.key,
    required this.connection,
    required this.bssid,
    required this.ssid,
    required this.channel,
  });

  final TelemetryConnection connection;
  final String bssid;
  final String ssid;
  final String channel;

  @override
  State<RadioLabPage> createState() => _RadioLabPageState();
}

class _RadioLabPageState extends State<RadioLabPage> {
  RadioLabStatus? _status;
  Timer? _ticker;
  bool _pending = true;
  bool _stopping = false;
  bool _finished = false;
  bool _polling = false;
  String? _error;
  String _kind = 'ssid_lab';

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (!_finished && _status?.sessionId.isNotEmpty == true) {
      unawaited(widget.connection.controlRadioLab(
        action: 'stop', sessionId: _status!.sessionId,
      ).then((_) {}, onError: (Object _) {}));
    }
    super.dispose();
  }

  Future<void> _check() async {
    setState(() { _pending = true; _error = null; });
    try {
      final result = await widget.connection.controlRadioLab(
        action: 'check', kind: _kind, bssid: widget.bssid,
      );
      if (!mounted) return;
      setState(() {
        _status = result;
        _error = result.accepted ? null : _describe(result.reason);
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法核验实验目标；请检查设备连接和实验配置。');
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _start() async {
    final profile = _status?.profileId ?? '';
    if (_pending || profile.isEmpty || _status?.accepted != true) return;
    setState(() { _pending = true; _error = null; });
    try {
      final next = await widget.connection.controlRadioLab(
        action: 'start',
        bssid: widget.bssid,
        profileId: profile,
        kind: _kind,
      );
      if (!mounted) return;
      setState(() {
        _status = next;
        _error = next.accepted ? null : _describe(next.reason);
      });
      if (next.accepted && next.sessionId.isNotEmpty) {
        _ticker?.cancel();
        _ticker = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_tick()));
      }
    } catch (_) {
      if (mounted) setState(() => _error = '无法启动实验；Kismet 不会由手机直接接管。');
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  Future<void> _tick() async {
    if (!mounted || _pending || _finished || _polling) return;
    _polling = true;
    final previous = _status;
    if (previous == null || previous.sessionId.isEmpty) {
      _polling = false;
      return;
    }
    try {
      final next = await widget.connection.controlRadioLab(
        action: _stopping ? 'status' : 'renew',
        sessionId: previous.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _status = next;
        if (!next.accepted && !_stopping) _error = _describe(next.reason);
      });
      if (const {'finished', 'degraded'}.contains(next.phase)) {
        _ticker?.cancel();
        setState(() => _finished = true);
      }
    } catch (_) {
      if (mounted) setState(() => _error = '与树莓派通信中断；本机租约将自动停止发射。');
    } finally {
      _polling = false;
    }
  }

  Future<void> _stop() async {
    final id = _status?.sessionId ?? '';
    if (id.isEmpty || _stopping) return;
    setState(() => _stopping = true);
    try {
      final next = await widget.connection.controlRadioLab(action: 'stop', sessionId: id);
      if (mounted) {
        setState(() {
          _status = next;
          if (!next.accepted) _error = '停止请求未获确认；树莓派将按租约自动停止。';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '停止请求未获确认；等待本机租约自动停止。');
    }
    await _tick();
  }

  String _describe(String reason) => switch (reason) {
    'not_authorized_lab_target' => '此 AP 未登记为射频隔离实验目标，不能启动主动测试。',
    'stale_observation' || 'observed_ap_not_fresh' =>
      '无线观测已过期，请返回探测模式刷新列表。',
    'mdk4_not_installed' => '树莓派尚未安装 MDK4，请检查镜像版本。',
    'radio_preflight_failed' => '外置网卡未就绪或身份不匹配。',
    'monitor_already_paused' => 'Kismet 已被其他操作暂停。',
    'another_lab_session' => '另一项无线实验正在运行。',
    'resource_pressure' => '设备资源压力过高，拒绝启动。',
    _ => reason.isEmpty ? '操作未获设备确认。' : reason,
  };

  bool get _hasSession => _status?.sessionId.isNotEmpty ?? false;
  bool get _running => const {'preparing', 'running', 'stopping', 'restoring'}.contains(_status?.phase);
  bool get _available => _status?.phase == 'available' && _status?.accepted == true;

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final elapsed = s != null && s.startedAtMs.toInt() > 0
        ? Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - s.startedAtMs.toInt())
        : Duration.zero;
    return Scaffold(
      appBar: AppBar(title: const Text('ACTIVE RADIO LAB')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('实验接入点', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(widget.ssid, style: Theme.of(context).textTheme.titleLarge),
                Text('BSSID  ' + widget.bssid),
                Text('最近观测信道  ' + widget.channel),
                if (s?.profileId.isNotEmpty == true) Text('授权配置  ' + s!.profileId),
                if (s?.simulatedBssid.isNotEmpty == true)
                  Text('实验 BSSID  ' + s!.simulatedBssid),
              ]),
            )),
            const SizedBox(height: 12),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('测试状态：' + (s?.phase ?? '核验中'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_hasSession) Text('会话 ID：' + s!.sessionId),
                if (_running) Text('已运行 ' + elapsed.inMinutes.toString() + ' 分 ' +
                    (elapsed.inSeconds % 60).toString() + ' 秒'),
                Text('MDK4：' + (s?.executorRunning == true ? '执行中' : '未运行')),
                Text('Kismet：' + (s?.kismetRestored == true ? '已恢复/待命' : '暂停或恢复中')),
                if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]),
            )),
            if (!_hasSession) ...[
              const SizedBox(height: 12),
              const Text('测试类型'),
              RadioListTile<String>(
                title: const Text('SSID 仿冒识别实验'),
                subtitle: const Text('仅用于本地预登记、射频隔离的实验 SSID'),
                value: 'ssid_lab',
                groupValue: _kind,
                onChanged: _pending ? null : (value) {
                  if (value != null) { setState(() => _kind = value); unawaited(_check()); }
                },
              ),
              RadioListTile<String>(
                title: const Text('Probe Request 实验'),
                subtitle: const Text('低频标准探测请求'),
                value: 'probe',
                groupValue: _kind,
                onChanged: _pending ? null : (value) {
                  if (value != null) { setState(() => _kind = value); unawaited(_check()); }
                },
              ),
            ],
            const SizedBox(height: 12),
            if (_pending) const Center(child: CircularProgressIndicator()),
            if (_available && !_pending)
              FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow),
                  label: const Text('启动授权实验')),
            if (_hasSession && !_finished)
              FilledButton.icon(
                onPressed: _stopping ? null : _stop,
                icon: const Icon(Icons.stop),
                label: Text(_stopping ? '正在停止并恢复监听…' : '结束测试'),
              ),
            if (_finished) ...[
              const SizedBox(height: 12),
              Card(child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('实验报告', style: Theme.of(context).textTheme.titleMedium),
                  Text('执行状态：' + (s?.reason ?? '未知')),
                  Text('监听恢复：' + (s?.kismetRestored == true ? '已确认' : '未确认，请检查设备状态')),
                  const Text('Kismet 暂停期间缺少独立抓包时，无法确认检测是否触发。'),
                  const Text('测试进程运行不等于检测成功或客户端受到影响。'),
                ]),
              )),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('返回探测模式')),
            ],
            if (!_hasSession && !_pending && !_available)
              OutlinedButton(onPressed: _check, child: const Text('重新核验授权')),
            const SizedBox(height: 12),
            const Text('仅适用于受控射频隔离靶场。最长会话 10 分钟；手机失联约 20 秒自动停止。'
                ' 不开放 Deauth、洪泛等高干扰模式。', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
