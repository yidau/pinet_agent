import 'dart:typed_data';

const timeSyncServiceUuid = '2f70e150-8c6b-4ee4-8f11-25d94aa85c00';
const timeSyncDeviceUuid = '2f70e150-8c6b-4ee4-8f11-25d94aa85c01';
const timeSyncRequestUuid = '2f70e150-8c6b-4ee4-8f11-25d94aa85c02';
const timeSyncResponseUuid = '2f70e150-8c6b-4ee4-8f11-25d94aa85c03';
const timeSyncResultUuid = '2f70e150-8c6b-4ee4-8f11-25d94aa85c04';
const timeSyncStatusUuid = '2f70e150-8c6b-4ee4-8f11-25d94aa85c05';

const maxTimeSamples = 5;
const _earliestPhoneTime = 1704067200000; // 2024-01-01 UTC.
const _latestPhoneTime = 4102444800000; // 2100-01-01 UTC, exclusive.
const _maxAdjustment = 5 * 366 * Duration.millisecondsPerDay;
const _maxElapsedMs = 5000;
const _maxDelayMs = 750;

class PhoneClock {
  final int _startUtcMs = DateTime.now().millisecondsSinceEpoch;
  final Stopwatch _elapsed = Stopwatch()..start();

  int utcMilliseconds() {
    final measured = _startUtcMs + _elapsed.elapsedMilliseconds;
    final wall = DateTime.now().millisecondsSinceEpoch;
    if ((wall - measured).abs() > 100) {
      throw const FormatException('手机时间在校时期间发生变化，请重新采样。');
    }
    if (measured < _earliestPhoneTime || measured >= _latestPhoneTime) {
      throw const FormatException('手机时间超出校时允许范围。');
    }
    return measured;
  }
}

class TimeSyncStatus {
  const TimeSyncStatus(this.nonce, this.phase);

  factory TimeSyncStatus.decode(List<int> packet) {
    final data = _read(packet, 10);
    if (data.getUint8(0) != 1) {
      throw const FormatException('树莓派校时协议版本不兼容。');
    }
    final phase = data.getUint8(1);
    final nonce = packet.sublist(2);
    if (phase > 2 || nonce.every((byte) => byte == 0)) {
      throw const FormatException('树莓派返回了无效的校时状态。');
    }
    return TimeSyncStatus(nonce, phase);
  }

  final List<int> nonce;
  final int phase;
}

enum TimeSyncOperation {
  probe(1),
  apply(2),
  applyBackward(3);

  const TimeSyncOperation(this.code);
  final int code;
}

Uint8List encodeTimeSyncRequest(
  TimeSyncOperation operation,
  List<int> nonce,
  int id,
  int timestamp,
) {
  final data = ByteData(19)
    ..setUint8(0, operation.code)
    ..setUint16(9, id)
    ..setInt64(11, timestamp);
  final bytes = data.buffer.asUint8List();
  bytes.setRange(1, 9, nonce);
  return bytes;
}

class TimeSample {
  const TimeSample({
    required this.nonce,
    required this.id,
    required this.t4,
    required this.offsetMs,
    required this.delayMs,
  });

  static TimeSample? fromResponse({
    required List<int> nonce,
    required int id,
    required int t1,
    required int t4,
    required List<int> packet,
  }) {
    if (packet.length != 18) return null;
    final data = _read(packet, 18);
    if (data.getUint16(0) != id) return null;
    final t2 = data.getInt64(2);
    final t3 = data.getInt64(10);
    final phoneElapsed = t4 - t1;
    final piElapsed = t3 - t2;
    if (phoneElapsed < 0 ||
        phoneElapsed > _maxElapsedMs ||
        piElapsed < 0 ||
        piElapsed > _maxElapsedMs ||
        t2 < t1 - _maxAdjustment - _maxDelayMs ||
        t2 > t4 + _maxAdjustment + _maxDelayMs) {
      return null;
    }
    final delay = phoneElapsed - piElapsed;
    final twiceOffset = (t2 - t1) + (t3 - t4);
    if (delay < 0 ||
        delay > _maxDelayMs ||
        twiceOffset.abs() > 2 * _maxAdjustment) {
      return null;
    }
    return TimeSample(
      nonce: nonce,
      id: id,
      t4: t4,
      offsetMs: twiceOffset ~/ 2,
      delayMs: delay,
    );
  }

  final List<int> nonce;
  final int id;
  final int t4;
  final int offsetMs;
  final int delayMs;

  bool get movesBackward => offsetMs > 0;
}

enum TimeSyncResultCode {
  applied,
  rejected,
  failed,
  confirmBackward,
  noResult,
  pending,
}

class TimeSyncResult {
  const TimeSyncResult(this.nonce, this.id, this.code, this.readbackUtcMs);

  factory TimeSyncResult.decode(List<int> packet) {
    final data = _read(packet, 19);
    final index = data.getUint8(10);
    final readback = data.getInt64(11);
    if (index >= TimeSyncResultCode.values.length ||
        (index == 0
            ? readback < _earliestPhoneTime || readback >= _latestPhoneTime
            : readback != 0)) {
      throw const FormatException('树莓派返回了无效的校时结果。');
    }
    return TimeSyncResult(
      packet.sublist(0, 8),
      data.getUint16(8),
      TimeSyncResultCode.values[index],
      readback,
    );
  }

  final List<int> nonce;
  final int id;
  final TimeSyncResultCode code;
  final int readbackUtcMs;

  bool matches(TimeSample sample) {
    if (sample.id != id) return false;
    for (var i = 0; i < nonce.length; i++) {
      if (sample.nonce[i] != nonce[i]) return false;
    }
    return true;
  }
}

ByteData _read(List<int> packet, int size) {
  if (packet.length != size) {
    throw const FormatException('树莓派返回的数据长度不正确。');
  }
  return ByteData.sublistView(Uint8List.fromList(packet));
}
