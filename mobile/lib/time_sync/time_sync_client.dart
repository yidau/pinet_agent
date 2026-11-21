import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../enrollment/enrollment_client.dart';
import '../enrollment/enrollment_profile.dart';
import 'time_sync_protocol.dart';

class TimeSyncClient {
  TimeSyncClient(this._ble, this.deviceId, {this.profile});

  static final service = Uuid.parse(timeSyncServiceUuid);
  static final _device = Uuid.parse(timeSyncDeviceUuid);
  static final _request = Uuid.parse(timeSyncRequestUuid);
  static final _response = Uuid.parse(timeSyncResponseUuid);
  static final _result = Uuid.parse(timeSyncResultUuid);
  static final _status = Uuid.parse(timeSyncStatusUuid);

  static const _timeout = Duration(seconds: 5);
  final FlutterReactiveBle _ble;
  final String deviceId;
  final EnrollmentProfile? profile;
  List<int>? _sessionKey;

  Future<void> authenticate() async {
    if (profile case final registered?) {
      final (_, key) = await EnrollmentClient(
        _ble,
        deviceId,
      ).resume(registered);
      _sessionKey = key;
    }
  }

  QualifiedCharacteristic _characteristic(Uuid id) => QualifiedCharacteristic(
    characteristicId: id,
    serviceId: service,
    deviceId: deviceId,
  );

  Future<List<int>> _read(Uuid id, [Duration timeout = _timeout]) =>
      _ble.readCharacteristic(_characteristic(id)).timeout(timeout);

  Future<void> _write(List<int> packet) {
    if (_sessionKey case final key?) {
      final tag = Hmac(sha256, key).convert([
        ...ascii.encode('piagent/time-sync/request/v3'),
        ...packet,
      ]).bytes;
      packet.setRange(1, 9, tag);
    } else if (profile != null) {
      throw const FormatException('请先验证已注册的手机身份。');
    }
    return _ble
        .writeCharacteristicWithResponse(
          _characteristic(_request),
          value: packet,
        )
        .timeout(_timeout);
  }

  Future<String> readDeviceInfo() async {
    final label = utf8.decode(await _read(_device));
    if (label.isEmpty || label.length > 20) {
      throw const FormatException('树莓派返回了无效的设备标识。');
    }
    return label;
  }

  Future<TimeSyncStatus> status({bool allowPairing = false}) async =>
      TimeSyncStatus.decode(
        await _read(
          _status,
          allowPairing ? const Duration(seconds: 30) : _timeout,
        ),
      );

  Future<TimeSample> sampleBest(
    PhoneClock clock,
    void Function(int) onSample,
  ) async {
    final ready = await status();
    if (ready.phase != 0) {
      throw const FormatException('树莓派正处理上一次校时，请稍后重试。');
    }
    TimeSample? best;
    for (var id = 1; id <= maxTimeSamples; id++) {
      onSample(id);
      final t1 = clock.utcMilliseconds();
      await _write(
        encodeTimeSyncRequest(TimeSyncOperation.probe, ready.nonce, id, t1),
      );
      final packet = await _read(_response);
      final t4 = clock.utcMilliseconds();
      final sample = TimeSample.fromResponse(
        nonce: ready.nonce,
        id: id,
        t1: t1,
        t4: t4,
        packet: packet,
      );
      if (sample != null && (best == null || sample.delayMs < best.delayMs)) {
        best = sample;
      }
    }
    if (best == null) {
      throw const FormatException('没有有效的校时样本，请重试。');
    }
    return best;
  }

  Future<void> commit(TimeSample sample, {required bool approveBackward}) {
    if (sample.movesBackward && !approveBackward) {
      throw const FormatException('需要确认回拨树莓派时间。');
    }
    return _write(
      encodeTimeSyncRequest(
        approveBackward
            ? TimeSyncOperation.applyBackward
            : TimeSyncOperation.apply,
        sample.nonce,
        sample.id,
        sample.t4,
      ),
    );
  }

  Future<TimeSyncResult?> awaitResult(TimeSample sample) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final result = TimeSyncResult.decode(await _read(_result));
      if (result.matches(sample) &&
          result.code != TimeSyncResultCode.pending &&
          result.code != TimeSyncResultCode.noResult) {
        return result;
      }
      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return null;
  }
}
