import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../enrollment/enrollment_client.dart';
import '../enrollment/enrollment_profile.dart';
import 'time_sync_client.dart';
import 'time_sync_protocol.dart';

enum AutomaticTimeSyncResult {
  aligned,
  synchronized,
  confirmBackward,
  bluetoothUnavailable,
  deviceUnavailable,
  unconfirmed,
  cancelled,
}

AutomaticTimeSyncResult? automaticTimeSyncWithoutWrite(int offsetMs) {
  if (offsetMs.abs() <= 500) return AutomaticTimeSyncResult.aligned;
  return offsetMs > 0 ? AutomaticTimeSyncResult.confirmBackward : null;
}

/// A single, cancellable attempt to synchronize the currently registered Pi.
class AutomaticTimeSync {
  final _ble = FlutterReactiveBle();
  final _cancelled = Completer<void>();
  bool _deadlineReached = false;
  bool _sentAdjustment = false;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  Future<T> _whileActive<T>(Future<T> pending) => Future.any([
    pending,
    _cancelled.future.then<T>((_) => throw const _CancelledSync()),
  ]);

  Future<AutomaticTimeSyncResult> synchronize(EnrollmentProfile profile) async {
    final timer = Timer(const Duration(seconds: 25), () {
      _deadlineReached = true;
      cancel();
    });
    try {
      final status = await _whileActive(
        _ble.statusStream
            .where((value) => value != BleStatus.unknown)
            .timeout(const Duration(seconds: 3))
            .first,
      );
      if (status != BleStatus.ready) {
        return AutomaticTimeSyncResult.bluetoothUnavailable;
      }
      final devices = await _scan();
      for (final device in devices.take(4)) {
        if (_cancelled.isCompleted) throw const _CancelledSync();
        final result = await _tryDevice(device.id, profile);
        if (result != null) return result;
      }
      return AutomaticTimeSyncResult.deviceUnavailable;
    } on _CancelledSync {
      if (_sentAdjustment) return AutomaticTimeSyncResult.unconfirmed;
      return _deadlineReached
          ? AutomaticTimeSyncResult.deviceUnavailable
          : AutomaticTimeSyncResult.cancelled;
    } catch (_) {
      return _sentAdjustment
          ? AutomaticTimeSyncResult.unconfirmed
          : AutomaticTimeSyncResult.deviceUnavailable;
    } finally {
      timer.cancel();
    }
  }

  Future<List<DiscoveredDevice>> _scan() async {
    if (_cancelled.isCompleted) throw const _CancelledSync();
    final nearby = <String, DiscoveredDevice>{};
    final scanDone = Completer<void>();
    final scan = _ble
        .scanForDevices(
          withServices: [EnrollmentClient.service],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(
          (device) => nearby[device.id] = device,
          onError: (Object error, StackTrace trace) {
            if (!scanDone.isCompleted) scanDone.completeError(error, trace);
          },
          onDone: () {
            if (!scanDone.isCompleted) scanDone.complete();
          },
        );
    try {
      await _whileActive(
        scanDone.future.timeout(const Duration(seconds: 3), onTimeout: () {}),
      );
    } finally {
      await scan.cancel();
    }
    return nearby.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  Future<AutomaticTimeSyncResult?> _tryDevice(
    String id,
    EnrollmentProfile profile,
  ) async {
    final connected = Completer<bool>();
    final disconnected = Completer<void>();
    void onDisconnect() {
      if (!connected.isCompleted) connected.complete(false);
      if (!disconnected.isCompleted) disconnected.complete();
    }

    final link = _ble
        .connectToDevice(id: id, connectionTimeout: const Duration(seconds: 5))
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected &&
                !connected.isCompleted) {
              connected.complete(true);
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              onDisconnect();
            }
          },
          onError: (Object _) => onDisconnect(),
          onDone: onDisconnect,
        );
    Future<T> whileConnected<T>(Future<T> pending) => _whileActive(
      Future.any([
        pending,
        disconnected.future.then<T>(
          (_) => throw const FormatException('蓝牙连接已断开。'),
        ),
      ]),
    );
    var authenticated = false;
    try {
      if (!await _whileActive(
        connected.future.timeout(
          const Duration(seconds: 6),
          onTimeout: () => false,
        ),
      )) {
        return null;
      }
      if (_cancelled.isCompleted || disconnected.isCompleted) return null;
      final client = TimeSyncClient(_ble, id, profile: profile);
      await whileConnected(
        client.authenticate().timeout(const Duration(seconds: 8)),
      );
      authenticated = true;
      final clock = PhoneClock();
      final sample = await whileConnected(
        client.sampleBest(clock, (_) {
          if (_cancelled.isCompleted) throw const _CancelledSync();
          if (disconnected.isCompleted) throw const FormatException('蓝牙连接已断开。');
        }),
      );
      if (_cancelled.isCompleted) throw const _CancelledSync();
      if (disconnected.isCompleted) {
        return AutomaticTimeSyncResult.deviceUnavailable;
      }
      final withoutWrite = automaticTimeSyncWithoutWrite(sample.offsetMs);
      if (withoutWrite != null) return withoutWrite;
      clock.utcMilliseconds();
      _sentAdjustment = true;
      try {
        await whileConnected(client.commit(sample, approveBackward: false));
      } on _CancelledSync {
        rethrow;
      } catch (_) {
        // The adjustment can have arrived even if its write acknowledgement was lost.
      }
      final result = await whileConnected(client.awaitResult(sample));
      return switch (result?.code) {
        TimeSyncResultCode.applied => AutomaticTimeSyncResult.synchronized,
        TimeSyncResultCode.confirmBackward =>
          AutomaticTimeSyncResult.confirmBackward,
        _ => AutomaticTimeSyncResult.unconfirmed,
      };
    } on _CancelledSync {
      rethrow;
    } catch (_) {
      if (!authenticated) return null;
      return _sentAdjustment
          ? AutomaticTimeSyncResult.unconfirmed
          : AutomaticTimeSyncResult.deviceUnavailable;
    } finally {
      await link.cancel();
    }
  }
}

class _CancelledSync implements Exception {
  const _CancelledSync();
}
