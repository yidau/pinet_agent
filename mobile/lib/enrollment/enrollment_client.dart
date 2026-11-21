import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../network.dart';
import 'enrollment_profile.dart';

Future<bool> requestBluetoothPermissions() async =>
    !Platform.isAndroid ||
    await const MethodChannel('net.piagent.piagent/time_sync')
            .invokeMethod<bool>('requestBluetoothPermissions') ==
        true;

class EnrollmentClient {
  EnrollmentClient(this._ble, this._deviceId);

  static const _native = MethodChannel('net.piagent.piagent/enrollment');
  static final service = Uuid.parse(enrollmentServiceUuid);
  static final _device = Uuid.parse('7ab410a0-fd6a-49f1-91bb-40e71e672101');
  static final _challenge = Uuid.parse('7ab410a0-fd6a-49f1-91bb-40e71e672102');
  static final _request = Uuid.parse('7ab410a0-fd6a-49f1-91bb-40e71e672103');
  static final _result = Uuid.parse('7ab410a0-fd6a-49f1-91bb-40e71e672104');
  static const _ioTimeout = Duration(seconds: 5);
  static const _exchangeTimeout = Duration(seconds: 60);

  final FlutterReactiveBle _ble;
  final String _deviceId;

  static Future<EnrollmentProfile> register(
    FlutterReactiveBle ble,
    EnrollmentQr qr,
    String deviceName,
  ) async {
    if (deviceName.isEmpty ||
        utf8.encode(deviceName).length > 64 ||
        deviceName.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('请输入有效的手机名称，长度不超过 64 字节。');
    }
    if (!await requestBluetoothPermissions()) {
      throw const FormatException('请授予蓝牙扫描和连接权限。');
    }
    final nearby = <String, DiscoveredDevice>{};
    final stopped = Completer<void>();
    final scan = ble
        .scanForDevices(
          withServices: [service],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(
          (device) => nearby[device.id] = device,
          onError: (Object error, StackTrace trace) {
            if (!stopped.isCompleted) stopped.completeError(error, trace);
          },
          onDone: () {
            if (!stopped.isCompleted) stopped.complete();
          },
        );
    try {
      await stopped.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } finally {
      await scan.cancel();
    }
    if (nearby.isEmpty) {
      throw const FormatException('没有找到附近的 PiAgent 注册服务。请检查树莓派和蓝牙。');
    }
    final devices = nearby.values.toList()
      ..sort((left, right) => right.rssi.compareTo(left.rssi));
    for (final device in devices.take(4)) {
      final client = EnrollmentClient(ble, device.id);
      final connected = Completer<bool>();
      var disconnected = false;
      final connection = ble
          .connectToDevice(
            id: device.id,
            connectionTimeout: const Duration(seconds: 10),
          )
          .listen(
            (update) {
              if (update.connectionState == DeviceConnectionState.connected &&
                  !connected.isCompleted) {
                connected.complete(true);
              } else if (update.connectionState ==
                  DeviceConnectionState.disconnected) {
                disconnected = true;
                if (!connected.isCompleted) connected.complete(false);
              }
            },
            onError: (Object _) {
              disconnected = true;
              if (!connected.isCompleted) connected.complete(false);
            },
            onDone: () {
              disconnected = true;
              if (!connected.isCompleted) connected.complete(false);
            },
          );
      try {
        if (!await connected.future.timeout(
          const Duration(seconds: 12),
          onTimeout: () => false,
        )) {
          continue;
        }
        final Uint8List? publicKey;
        try {
          publicKey = await client._pinnedKey(qr.piId, qr.fingerprint);
        } catch (_) {
          continue;
        }
        if (publicKey == null) continue;
        final (profile, _) = await client._exchange(
          piId: qr.piId,
          fingerprint: qr.fingerprint,
          publicKey: publicKey,
          deviceName: deviceName,
          registrationSecret: qr.secret,
        );
        if (disconnected) {
          throw const FormatException('蓝牙已断开，请重新扫描二维码注册。');
        }
        await profile.save();
        return profile;
      } finally {
        await connection.cancel();
      }
    }
    throw const FormatException('附近设备与二维码中的树莓派身份不匹配。');
  }

  Future<(EnrollmentProfile, Uint8List)> resume(
    EnrollmentProfile profile,
  ) async {
    final publicKey = await _pinnedKey(profile.piId, profile.fingerprint);
    if (publicKey == null) {
      throw const FormatException('蓝牙设备与已注册的树莓派身份不匹配。');
    }
    final (updated, key) = await _exchange(
      piId: profile.piId,
      fingerprint: profile.fingerprint,
      publicKey: publicKey,
      deviceName: profile.deviceName,
    );
    if (updated.phoneId != profile.phoneId) {
      throw const FormatException('树莓派返回了不同的手机身份。');
    }
    return (updated, key);
  }

  QualifiedCharacteristic _characteristic(Uuid id) => QualifiedCharacteristic(
    characteristicId: id,
    serviceId: service,
    deviceId: _deviceId,
  );

  Future<List<int>> _read(Uuid id) =>
      _ble.readCharacteristic(_characteristic(id)).timeout(_ioTimeout);

  Future<void> _write(List<int> packet, [Duration timeout = _ioTimeout]) => _ble
      .writeCharacteristicWithResponse(_characteristic(_request), value: packet)
      .timeout(timeout);

  Json _decode(List<int> data) {
    try {
      return jsonObject(jsonDecode(utf8.decode(data)), 'enrollment');
    } on FormatException {
      throw const FormatException('树莓派返回了无效的注册数据。');
    }
  }

  Future<Uint8List?> _pinnedKey(String piId, String fingerprint) async {
    final device = _decode(await _read(_device));
    final publicKey = device['public_key'];
    if (device['version'] != 1 ||
        device['device_id'] != piId ||
        device['public_key_fingerprint'] != fingerprint ||
        publicKey is! String) {
      return null;
    }
    final bytes = enrollmentBytes(publicKey, length: 65);
    return bytes.first == 4 && 'sha256:${sha256.convert(bytes)}' == fingerprint
        ? bytes
        : null;
  }

  Future<T> _nativeValue<T>(String method, Map<String, Object> args) async =>
      await _native.invokeMethod<T>(method, args).timeout(_ioTimeout) ??
      (throw const FormatException('无法使用手机安全密钥。'));

  Future<(EnrollmentProfile, Uint8List)> _exchange({
    required String piId,
    required String fingerprint,
    required Uint8List publicKey,
    required String deviceName,
    Uint8List? registrationSecret,
  }) async {
    final challenge = _decode(await _read(_challenge));
    final nonce = challenge['nonce'];
    final ephemeral = challenge['ephemeral'];
    final signature = challenge['signature'];
    if (nonce is! String || ephemeral is! String || signature is! String) {
      throw const FormatException('树莓派返回了无效的身份挑战。');
    }
    final salt = enrollmentBytes(nonce, length: 32);
    final serverEphemeral = enrollmentBytes(ephemeral, length: 65);
    final signed = Uint8List.fromList(
      utf8.encode(
        ['piagent/enrollment/challenge/v1', piId, nonce, ephemeral].join('\n'),
      ),
    );
    if (serverEphemeral.first != 4 ||
        !await _nativeValue<bool>('verify', {
          'publicKey': publicKey,
          'data': signed,
          'signature': enrollmentBytes(signature, maxLength: 80),
        })) {
      throw const FormatException('树莓派身份验证失败。');
    }

    final alias =
        'piagent-enrollment-${sha256.convert(utf8.encode('$piId\n$fingerprint'))}';
    final random = Random.secure();
    final session = enrollmentBase64(
      List<int>.generate(18, (_) => random.nextInt(256)),
    );
    try {
      final clientPublic = enrollmentBase64(
        await _nativeValue<Uint8List>('publicKey', {'alias': alias}),
      );
      final clientEphemeral = enrollmentBase64(
        await _nativeValue<Uint8List>('ephemeralPublicKey', {
          'session': session,
        }),
      );
      final mode = registrationSecret == null ? 'resume' : 'register';
      final transcript = Uint8List.fromList(
        utf8.encode(
          [
            'piagent/enrollment/request/v1',
            piId,
            nonce,
            ephemeral,
            mode,
            clientPublic,
            clientEphemeral,
            enrollmentBase64(utf8.encode(deviceName)),
          ].join('\n'),
        ),
      );
      final key = registrationSecret == null
          ? null
          : Hmac(
              sha256,
              registrationSecret,
            ).convert(ascii.encode('piagent/enrollment/key/v1')).bytes;
      final proof = key == null
          ? ''
          : enrollmentBase64(Hmac(sha256, key).convert(transcript).bytes);
      final signedRequest = await _nativeValue<Uint8List>('sign', {
        'alias': alias,
        'data': transcript,
      });
      final payload = utf8.encode(
        jsonEncode({
          'mode': mode,
          'nonce': nonce,
          'device_name': deviceName,
          'public_key': clientPublic,
          'ephemeral': clientEphemeral,
          'proof': proof,
          'signature': enrollmentBase64(signedRequest),
        }),
      );
      final clock = Stopwatch()..start();
      void checkDeadline() {
        if (clock.elapsed >= _exchangeTimeout) {
          throw const FormatException('蓝牙注册超时，请重试。');
        }
      }

      await _write([1]);
      for (var offset = 0; offset < payload.length; offset += 19) {
        checkDeadline();
        await _write([
          2,
          ...payload.getRange(offset, min(offset + 19, payload.length)),
        ]);
      }
      await _write([3], const Duration(seconds: 15));
      final sealed = await _sealedResult(checkDeadline);
      final decoded = await _nativeValue<Uint8List>('decrypt', {
        'session': session,
        'serverPublicKey': serverEphemeral,
        'salt': salt,
        'associatedData': transcript,
        'sealed': sealed,
      });
      final json = _decode(decoded);
      final keyText = json['ble_key'];
      if (keyText is! String) throw const FormatException('树莓派没有返回蓝牙会话密钥。');
      return (
        EnrollmentProfile.decode(
          json,
          piId: piId,
          fingerprint: fingerprint,
          deviceName: deviceName,
        ),
        enrollmentBytes(keyText, length: 32),
      );
    } finally {
      await _native
          .invokeMethod<void>('discardEphemeral', {'session': session})
          .timeout(_ioTimeout);
    }
  }

  Future<Uint8List> _sealedResult(void Function() checkDeadline) async {
    final contents = BytesBuilder(copy: false);
    int? total;
    do {
      checkDeadline();
      final offset = contents.length;
      if (offset != 0) await _write([4, offset >> 8, offset & 255]);
      final packet = await _read(_result);
      if (packet.length < 3 || packet.length > 20) {
        throw const FormatException('蓝牙注册响应长度无效。');
      }
      final status = packet[0];
      if (status == 2) {
        throw const FormatException('树莓派拒绝了授权。请检查二维码和手机的注册状态。');
      }
      if (status == 0 || status == 3) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }
      final size = (packet[1] << 8) | packet[2];
      if (status != 1 ||
          size < 28 ||
          size > 16384 ||
          (total != null && total != size) ||
          packet.length - 3 != min(17, size - offset)) {
        throw const FormatException('蓝牙注册响应格式无效。');
      }
      total = size;
      contents.add(packet.sublist(3));
    } while (total == null || contents.length < total);
    return contents.takeBytes();
  }
}
