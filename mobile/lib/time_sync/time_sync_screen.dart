import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:material_ui/material_ui.dart';

import 'time_sync_client.dart';
import 'time_sync_protocol.dart';

class TimeSyncScreen extends StatefulWidget {
  const TimeSyncScreen({super.key});

  @override
  State<TimeSyncScreen> createState() => _TimeSyncScreenState();
}

class _TimeSyncScreenState extends State<TimeSyncScreen> {
  static const _permissions = MethodChannel('net.piagent.piagent/time_sync');
  static const _waitingForResult = '暂时无法确认校时结果，重新连接后可查询。';
  late final _ble = FlutterReactiveBle();
  final _nearby = <String, DiscoveredDevice>{};
  final _pending = <String, TimeSample>{};
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  Timer? _scanTimer;
  TimeSyncClient? _client;
  int _scanEpoch = 0;
  int _connectionEpoch = 0;
  bool _scanning = false;
  bool _disconnecting = false;
  bool _ready = false;
  bool _working = false;
  String _status = '打开蓝牙，扫描附近的树莓派。';
  String? _deviceLabel;
  TimeSample? _sample;
  int? _readback;

  bool _isCurrent(int epoch) => mounted && epoch == _connectionEpoch;

  @override
  void dispose() {
    _scanTimer?.cancel();
    unawaited(_scan?.cancel());
    unawaited(_connection?.cancel());
    super.dispose();
  }

  Future<void> _startScan() async {
    final epoch = ++_scanEpoch;
    setState(() {
      _scanning = true;
      _nearby.clear();
      _status = '正在扫描树莓派…';
    });
    try {
      final allowed =
          !Platform.isAndroid ||
          await _permissions.invokeMethod<bool>(
                'requestBluetoothPermissions',
              ) ==
              true;
      if (!mounted || epoch != _scanEpoch) return;
      if (!allowed) {
        await _stopScan(message: '请授予蓝牙扫描和连接所需的权限。');
        return;
      }
      _scan = _ble
          .scanForDevices(
            withServices: [TimeSyncClient.service],
            scanMode: ScanMode.lowLatency,
            requireLocationServicesEnabled: false,
          )
          .listen(
            (device) {
              if (!mounted || epoch != _scanEpoch) return;
              setState(() => _nearby[device.id] = device);
            },
            onError: (Object _) {
              if (epoch == _scanEpoch) {
                unawaited(_stopScan(message: '扫描失败，请检查蓝牙和权限，再重试。'));
              }
            },
          );
      _scanTimer = Timer(const Duration(seconds: 8), () {
        if (epoch == _scanEpoch) unawaited(_stopScan());
      });
    } catch (_) {
      if (epoch == _scanEpoch) {
        await _stopScan(message: '无法启动扫描，请检查蓝牙权限。');
      }
    }
  }

  Future<void> _stopScan({String? message}) async {
    ++_scanEpoch;
    _scanTimer?.cancel();
    final scan = _scan;
    _scan = null;
    if (mounted) {
      setState(() {
        _scanning = false;
        _status = message ?? (_nearby.isEmpty ? '未找到树莓派。' : '选择要校时的树莓派。');
      });
    }
    await scan?.cancel();
  }

  Future<void> _connect(DiscoveredDevice device) async {
    if (_client != null || _disconnecting) return;
    final epoch = ++_connectionEpoch;
    final client = TimeSyncClient(_ble, device.id);
    setState(() {
      _client = client;
      _ready = false;
      _working = true;
      _deviceLabel = null;
      _sample = null;
      _readback = null;
      _status = '正在连接树莓派…';
    });
    try {
      if (_scanning) await _stopScan(message: '正在连接树莓派…');
      if (!_isCurrent(epoch)) return;
      var checking = false;
      _connection = _ble
          .connectToDevice(
            id: device.id,
            connectionTimeout: const Duration(seconds: 12),
          )
          .listen(
            (update) {
              if (!_isCurrent(epoch)) return;
              switch (update.connectionState) {
                case DeviceConnectionState.connected:
                  if (!checking) {
                    checking = true;
                    unawaited(_checkDevice(client, epoch));
                  }
                case DeviceConnectionState.disconnected:
                  unawaited(_disconnect(epoch, '蓝牙连接已断开。'));
                case DeviceConnectionState.connecting:
                case DeviceConnectionState.disconnecting:
                  break;
              }
            },
            onError: (Object _) => unawaited(_disconnect(epoch, '无法连接树莓派。')),
            onDone: () => unawaited(_disconnect(epoch, '蓝牙连接已断开。')),
          );
    } catch (_) {
      await _disconnect(epoch, '无法连接树莓派。');
    }
  }

  Future<void> _disconnect(int epoch, String message) async {
    if (!_isCurrent(epoch)) return;
    ++_connectionEpoch;
    final connection = _connection;
    _connection = null;
    final hasPendingResult = _pending.containsKey(_client?.deviceId);
    setState(() {
      _client = null;
      _ready = false;
      _working = false;
      _disconnecting = true;
      _status = hasPendingResult ? _waitingForResult : message;
    });
    try {
      await connection?.cancel();
    } catch (_) {
      // The local connection epoch was already invalidated.
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  Future<void> _checkDevice(TimeSyncClient client, int epoch) async {
    setState(() => _status = '正在验证蓝牙配对和设备授权…');
    try {
      final label = await client.readDeviceInfo();
      if (!_isCurrent(epoch)) return;
      await client.status(allowPairing: true);
      if (!_isCurrent(epoch)) return;
      setState(() {
        _deviceLabel = label;
        _ready = true;
        _status = '设备已授权，可以开始校时。';
      });
      final pending = _pending[client.deviceId];
      if (pending != null) await _readResult(client, pending, epoch);
    } catch (_) {
      if (!_isCurrent(epoch)) return;
      setState(() {
        _status = _ready
            ? _waitingForResult
            : '无法验证设备。请完成系统蓝牙配对，并由树莓派管理员授权此手机。';
      });
    } finally {
      if (_isCurrent(epoch)) setState(() => _working = false);
    }
  }

  Future<void> _synchronize() async {
    final client = _client;
    if (client == null || _working || !_ready) return;
    final epoch = _connectionEpoch;
    setState(() {
      _working = true;
      _sample = null;
      _readback = null;
      _status = '正在准备校时…';
    });
    var committed = false;
    try {
      final clock = PhoneClock();
      final sample = await client.sampleBest(clock, (index) {
        if (!_isCurrent(epoch)) throw const FormatException('蓝牙连接已断开。');
        setState(() => _status = '正在采集第 $index/$maxTimeSamples 个样本…');
      });
      if (!_isCurrent(epoch)) return;
      setState(() => _sample = sample);
      final approveBackward =
          sample.movesBackward && await _confirmBackward(sample);
      if (!_isCurrent(epoch)) return;
      if (sample.movesBackward && !approveBackward) {
        await _disconnect(epoch, '已取消回拨。请重新连接后再校时。');
        return;
      }
      clock.utcMilliseconds();
      committed = true;
      _pending[client.deviceId] = sample;
      setState(() => _status = '正在等待树莓派确认校时结果…');
      try {
        await client.commit(sample, approveBackward: approveBackward);
      } catch (_) {
        // The write may have reached the device before its acknowledgement failed.
        if (!_isCurrent(epoch)) return;
      }
      if (_isCurrent(epoch)) await _readResult(client, sample, epoch);
    } catch (error) {
      if (!_isCurrent(epoch)) return;
      if (committed) {
        setState(() => _status = _waitingForResult);
      } else {
        final message = error is FormatException ? error.message : '采样失败。';
        await _disconnect(epoch, '$message 请重新连接后再校时。');
      }
    } finally {
      if (_isCurrent(epoch)) setState(() => _working = false);
    }
  }

  Future<bool> _confirmBackward(TimeSample sample) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认回拨树莓派时间'),
        content: Text('树莓派时间超前约 ${sample.offsetMs} 毫秒。确认后将回拨系统时间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认回拨'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _readResult(
    TimeSyncClient client,
    TimeSample sample,
    int epoch,
  ) async {
    final result = await client.awaitResult(sample);
    if (!_isCurrent(epoch)) return;
    if (result == null) {
      setState(() => _status = _waitingForResult);
      return;
    }
    _pending.remove(client.deviceId);
    setState(() {
      _sample = sample;
      _readback = result.code == TimeSyncResultCode.applied
          ? result.readbackUtcMs
          : null;
      _status = switch (result.code) {
        TimeSyncResultCode.applied => '校时成功',
        TimeSyncResultCode.rejected => '树莓派拒绝了校时请求，请重新采样。',
        TimeSyncResultCode.failed => '树莓派报告校时失败，请核对设备时间。',
        TimeSyncResultCode.confirmBackward => '树莓派要求确认回拨，请重新采样并确认。',
        TimeSyncResultCode.noResult ||
        TimeSyncResultCode.pending => _waitingForResult,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙校时')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_deviceLabel case final label?) Text(label),
            Semantics(liveRegion: true, child: Text(_status)),
            if (_sample case final sample?) ...[
              Text('树莓派相对手机的偏移 ${sample.offsetMs} 毫秒'),
              Text('估算往返延迟 ${sample.delayMs} 毫秒'),
            ],
            if (_readback case final readback?)
              Text(
                '校准后读取时间 ${DateTime.fromMillisecondsSinceEpoch(readback, isUtc: true).toIso8601String()}',
              ),
            const SizedBox(height: 16),
            if (_client == null) ...[
              FilledButton(
                onPressed: _disconnecting
                    ? null
                    : (_scanning ? _stopScan : _startScan),
                child: Text(_scanning ? '停止扫描' : '扫描树莓派'),
              ),
              for (final device in _nearby.values)
                ListTile(
                  title: Text(device.name.isEmpty ? 'PiAgent' : device.name),
                  subtitle: Text(device.id),
                  onTap: _disconnecting ? null : () => _connect(device),
                ),
            ] else ...[
              FilledButton(
                onPressed: _ready && !_working ? _synchronize : null,
                child: const Text('开始校时'),
              ),
              TextButton(
                onPressed: () => _disconnect(_connectionEpoch, '蓝牙连接已断开。'),
                child: const Text('断开'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
