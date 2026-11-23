import 'dart:async';
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';

import '../enrollment/enrollment_profile.dart';
import 'message_repository.dart';
import 'proto/monitoring.pbgrpc.dart';

enum TelemetryPhase {
  stopped,
  connecting,
  live,
  retrying,
  denied,
  incompatible,
}

class TelemetryTarget {
  const TelemetryTarget({
    required this.host,
    required this.deviceKey,
    required this.phoneId,
    required this.token,
    required this.caPem,
  });

  factory TelemetryTarget.fromEnrollment(EnrollmentProfile profile) =>
      TelemetryTarget(
        host: profile.mcpUrl.host,
        deviceKey: '${profile.fingerprint}/${profile.phoneId}',
        phoneId: profile.phoneId,
        token: profile.token,
        caPem: profile.caPem,
      );

  final String host;
  final String deviceKey;
  final String phoneId;
  final String token;
  final String caPem;

  bool sameSession(TelemetryTarget other) =>
      deviceKey == other.deviceKey &&
      host == other.host &&
      token == other.token &&
      caPem == other.caPem;
}

abstract interface class TelemetryTransport {
  Stream<TelemetryMessage> subscribe(SubscribeRequest request);
  Future<void> close();
}

class _GrpcTransport implements TelemetryTransport {
  _GrpcTransport(this.target)
    : _channel = ClientChannel(
        target.host,
        port: 9443,
        options: ChannelOptions(
          connectTimeout: const Duration(seconds: 6),
          credentials: ChannelCredentials.secure(
            certificates: utf8.encode(target.caPem),
          ),
        ),
      );

  final TelemetryTarget target;
  final ClientChannel _channel;

  @override
  Stream<TelemetryMessage> subscribe(SubscribeRequest request) =>
      TelemetryServiceClient(_channel).subscribe(
        request,
        options: CallOptions(
          metadata: {'authorization': 'Bearer ${target.token}'},
        ),
      );

  @override
  Future<void> close() => _channel.terminate();
}

class TelemetryConnection extends ChangeNotifier {
  TelemetryConnection({
    MessageRepository? repository,
    TelemetryTransport Function(TelemetryTarget)? createTransport,
  }) : _repository = repository ?? MessageRepository(),
       _createTransport = createTransport ?? _GrpcTransport.new;

  final MessageRepository _repository;
  final TelemetryTransport Function(TelemetryTarget) _createTransport;
  TelemetryTarget? _target;
  TelemetryTransport? _transport;
  StreamSubscription<void>? _stream;
  Timer? _retry;
  int _generation = 0;
  int _backoffSeconds = 1;
  bool _foreground = true;
  bool _requested = false;
  bool _disposed = false;
  EventCursor? _cursor;
  MonitoringSnapshot? _snapshot;
  List<StoredTelemetryEvent> _messages = const [];
  TelemetryPhase _phase = TelemetryPhase.stopped;
  bool _storageError = false;

  MonitoringSnapshot? get snapshot => _snapshot;
  List<StoredTelemetryEvent> get messages => _messages;
  TelemetryPhase get phase => _phase;
  bool get storageError => _storageError;
  bool get isConfigured => _target != null;
  bool get isRequested => _requested;
  int get unreadCount => _messages.where((message) => message.unread).length;

  void useTarget(TelemetryTarget? target) {
    final previous = _target;
    if (target == null
        ? previous == null
        : previous?.sameSession(target) == true) {
      return;
    }
    _endTransport();
    _target = target;
    _requested = target != null;
    _cursor = null;
    _snapshot = null;
    _messages = const [];
    _storageError = false;
    _phase = TelemetryPhase.stopped;
    if (target != null && _foreground) {
      _connect();
    } else {
      notifyListeners();
    }
  }

  void start() {
    if (_target == null) return;
    if (_requested) return;
    _requested = true;
    if (_foreground) _connect();
  }

  void stop() {
    _requested = false;
    _endTransport();
    _phase = TelemetryPhase.stopped;
    notifyListeners();
  }

  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) {
      _endTransport();
      _phase = TelemetryPhase.stopped;
      notifyListeners();
    } else if (_requested) {
      _connect();
    }
  }

  void _connect() {
    final target = _target;
    if (target == null) return;
    _endTransport();
    _backoffSeconds = 1;
    _phase = TelemetryPhase.connecting;
    notifyListeners();
    unawaited(_loadHistory(target, _generation));
  }

  Future<void> _loadHistory(TelemetryTarget target, int generation) async {
    try {
      final archive = await _repository.load(target.deviceKey);
      if (!_isCurrent(generation)) return;
      _cursor = archive.cursor;
      _messages = List.unmodifiable(archive.messages);
      _storageError = false;
    } catch (_) {
      if (!_isCurrent(generation)) return;
      _storageError = true;
    }
    notifyListeners();
    _subscribe(target, generation);
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _subscribe(TelemetryTarget target, int generation) {
    if (!_isCurrent(generation)) return;
    try {
      final transport = _createTransport(target);
      _transport = transport;
      final request = SubscribeRequest(
        deviceId: target.phoneId,
        lastBootId: _cursor?.bootId,
        lastEventSequence: _cursor?.sequence,
      );
      _stream = transport
          .subscribe(request)
          .timeout(const Duration(seconds: 12))
          .asyncMap((message) => _receive(message, target, generation))
          .listen(
            (_) {},
            onDone: () => _streamEnded(generation),
            onError: (Object error) => _streamEnded(generation, error),
            cancelOnError: true,
          );
    } catch (error) {
      _streamEnded(generation, error);
    }
  }

  Future<void> _receive(
    TelemetryMessage message,
    TelemetryTarget target,
    int generation,
  ) async {
    if (!_isCurrent(generation)) return;
    switch (message.whichPayload()) {
      case TelemetryMessage_Payload.snapshot:
        final snapshot = message.snapshot;
        if (snapshot.schemaVersion != 1 || snapshot.bootId.isEmpty) {
          throw const FormatException('Unsupported telemetry schema.');
        }
        final previous = _snapshot;
        if (_phase != TelemetryPhase.live ||
            previous == null ||
            previous.bootId != snapshot.bootId ||
            previous.sequence < snapshot.sequence) {
          _snapshot = snapshot;
        }
        _phase = TelemetryPhase.live;
        _backoffSeconds = 1;
        notifyListeners();
      case TelemetryMessage_Payload.event:
        final event = message.event;
        if (event.eventId.isEmpty ||
            event.bootId.isEmpty ||
            event.sequence <= (_cursor?.sequence ?? Int64.ZERO)) {
          return;
        }
        await _store(target, generation, event, (
          bootId: event.bootId,
          sequence: event.sequence,
        ));
      case TelemetryMessage_Payload.historyGap:
        final gap = message.historyGap;
        final sequence = gap.throughEventSequence;
        if (gap.reason != 'cursor_reset' &&
            sequence <= (_cursor?.sequence ?? Int64.ZERO)) {
          return;
        }
        final event = MonitoringEvent(
          bootId: gap.bootId,
          eventId: 'gap:${gap.bootId}:${gap.reason}:$sequence',
          sequence: sequence,
          timestampMs: _snapshot?.timestampMs,
          eventType: 'history_gap',
          priority: EventPriority.P1,
          source: 'telemetry',
          description: gap.reason == 'cursor_reset'
              ? '设备的事件历史已重新建立，正在读取现有记录。'
              : '部分事件已超出设备的保留范围，消息历史可能不完整。',
        );
        await _store(target, generation, event, (
          bootId: gap.bootId,
          sequence: sequence,
        ));
      case TelemetryMessage_Payload.notSet:
        break;
    }
  }

  Future<void> _store(
    TelemetryTarget target,
    int generation,
    MonitoringEvent event,
    EventCursor cursor,
  ) async {
    final bool inserted;
    try {
      inserted = await _repository.ingest(target.deviceKey, event, cursor);
    } catch (_) {
      if (_isCurrent(generation)) {
        _storageError = true;
        notifyListeners();
      }
      // Reconnect with the last durable cursor to recover the missing event.
      throw StateError('Telemetry history could not be saved.');
    }
    if (!_isCurrent(generation)) return;
    _cursor = cursor;
    _storageError = false;
    if (inserted) {
      _messages = List.unmodifiable([
        StoredTelemetryEvent(event, unread: true),
        ..._messages.take(_repository.maximumEvents - 1),
      ]);
    }
    notifyListeners();
  }

  Future<void> markRead(StoredTelemetryEvent item) async {
    final target = _target;
    if (!item.unread || target == null) return;
    try {
      await _repository.markRead(target.deviceKey, item.event.eventId);
      if (_disposed || !identical(_target, target)) return;
      _messages = List.unmodifiable([
        for (final message in _messages)
          if (message.event.eventId == item.event.eventId)
            StoredTelemetryEvent(message.event, unread: false)
          else
            message,
      ]);
    } catch (_) {
      if (_disposed || !identical(_target, target)) return;
      _storageError = true;
    }
    notifyListeners();
  }

  void _streamEnded(int generation, [Object? error]) {
    if (!_isCurrent(generation)) return;
    _endTransport();
    if (error is GrpcError &&
        (error.code == StatusCode.unauthenticated ||
            error.code == StatusCode.permissionDenied)) {
      _phase = TelemetryPhase.denied;
      _requested = false;
    } else if (error is FormatException) {
      _phase = TelemetryPhase.incompatible;
      _requested = false;
    } else {
      _phase = TelemetryPhase.retrying;
      final target = _target!;
      final next = _generation;
      _retry = Timer(Duration(seconds: _backoffSeconds), () {
        _subscribe(target, next);
      });
      _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
    }
    notifyListeners();
  }

  void _endTransport() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _stream?.cancel().ignore();
    _stream = null;
    _transport?.close().ignore();
    _transport = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _endTransport();
    super.dispose();
  }
}
