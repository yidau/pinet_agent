import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:grpc/grpc.dart';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../telemetry/proto/monitoring.pbgrpc.dart';
import 'enrollment_client.dart';
import 'enrollment_profile.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key, this.profile, required this.onRegistered});

  final EnrollmentProfile? profile;
  final ValueChanged<EnrollmentProfile> onRegistered;

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  late final _deviceName = TextEditingController(
    text:
        widget.profile?.deviceName ??
        (Platform.isIOS ? 'iPhone' : 'Android 手机'),
  );
  late final _ble = FlutterReactiveBle();
  late var _profile = widget.profile;
  bool _working = false;
  String? _status;

  @override
  void dispose() {
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final name = _deviceName.text.trim();
    final qr = await Navigator.of(
      context,
    ).push<EnrollmentQr>(MaterialPageRoute(builder: (_) => const _QrScanner()));
    if (qr == null || !mounted) return;
    setState(() {
      _working = true;
      _status = '正在发现树莓派并通过蓝牙注册…';
    });
    try {
      final profile = await EnrollmentClient.register(
        _ble,
        qr,
        name,
      ).whenComplete(() => qr.secret.fillRange(0, qr.secret.length, 0));
      if (!mounted) return;
      setState(() => _profile = profile);
      widget.onRegistered(profile);
      await _addWifi(profile);
    } on FormatException catch (error) {
      if (mounted) setState(() => _status = error.message);
    } catch (_) {
      if (mounted) setState(() => _status = '蓝牙注册失败。请确认蓝牙已开启且树莓派在附近，再重试。');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _addWifi(EnrollmentProfile profile) async {
    setState(() {
      _working = true;
      _status = '手机已注册。请在系统提示中确认添加热点 ${profile.ssid}。';
    });
    try {
      final accepted = await profile.connectWifi();
      if (!mounted) return;
      if (accepted) {
        await _checkConnection(profile);
      } else {
        setState(() => _status = '网络配置未获系统确认。可以再次添加热点。');
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(
        () => _status = error.code == 'wifi_unsupported'
            ? '此系统不支持由 PiAgent 添加热点配置。'
            : '未能添加 PiAgent 热点，请重试。',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _checkConnection(EnrollmentProfile profile) async {
    final unreachable =
        '未能连接树莓派遥测服务。请连接热点 ${profile.ssid} 后重试。'
        '如果手机仍使用旧的热点配置，请在系统设置中移除旧配置，再点「添加热点到手机」。';
    setState(() {
      _working = true;
      _status = '正在验证 gRPC 遥测连接…';
    });
    try {
      final channel = ClientChannel(
        profile.telemetryUrl.host,
        port: profile.telemetryUrl.port,
        options: ChannelOptions(
          connectTimeout: const Duration(seconds: 6),
          credentials: ChannelCredentials.secure(
            certificates: utf8.encode(profile.caPem),
          ),
        ),
      );
      try {
        final messages = TelemetryServiceClient(channel).subscribe(
          SubscribeRequest(deviceId: profile.phoneId),
          options: CallOptions(
            metadata: {'authorization': 'Bearer ${profile.token}'},
          ),
        );
        final first = await messages.first.timeout(const Duration(seconds: 12));
        if (first.whichPayload() != TelemetryMessage_Payload.snapshot ||
            first.snapshot.schemaVersion != 1) {
          throw const FormatException('树莓派未返回兼容的遥测快照。');
        }
      } finally {
        await channel.terminate();
      }
      if (mounted) setState(() => _status = 'gRPC 遥测连接成功，已收到设备快照。');
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(
        () => _status =
            error.message.contains('HTTP 401') ||
                error.message.contains('HTTP 403')
            ? '树莓派拒绝了此手机的访问授权。'
            : unreachable,
      );
    } catch (_) {
      if (mounted) setState(() => _status = unreachable);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        appBar: AppBar(title: const Text('手机注册')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (profile != null) ...[
                Text(
                  profile.deviceName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('手机 ID ${profile.phoneId}'),
                Text('树莓派 ${profile.piId}'),
                Text('管理热点 ${profile.ssid}'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _working ? null : () => _addWifi(profile),
                  child: const Text('添加热点到手机'),
                ),
                OutlinedButton(
                  onPressed: _working ? null : () => _checkConnection(profile),
                  child: const Text('测试 gRPC 遥测连接'),
                ),
                const SizedBox(height: 16),
              ],
              if (_working) const LinearProgressIndicator(),
              if (_status case final status?) ...[
                Semantics(liveRegion: true, child: Text(status)),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _deviceName,
                enabled: !_working,
                decoration: const InputDecoration(labelText: '手机名称'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _working ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫描树莓派的永久二维码'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrScanner extends StatefulWidget {
  const _QrScanner();

  @override
  State<_QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<_QrScanner> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _detected = false;
  bool _invalid = false;

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  void _handle(BarcodeCapture capture) {
    if (_detected || !mounted) return;
    for (final code in capture.barcodes) {
      if (code.rawValue case final raw?) {
        try {
          final qr = EnrollmentQr.parse(raw);
          _detected = true;
          Navigator.pop(context, qr);
          return;
        } on FormatException {
          if (!_invalid) setState(() => _invalid = true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描永久二维码')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _handle,
              errorBuilder: (context, error) =>
                  const Center(child: Text('无法打开相机。请在系统设置中确认相机权限。')),
            ),
          ),
          if (_invalid)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('这不是有效的 PiAgent 永久二维码。'),
            ),
        ],
      ),
    ),
  );
}
