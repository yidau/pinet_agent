import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    this.port = 9443,
    required this.deviceKey,
    required this.phoneId,
    required this.token,
    required this.caPem,
  });

  factory TelemetryTarget.fromEnrollment(EnrollmentProfile profile) =>
      TelemetryTarget(
        host: profile.telemetryUrl.host,
        port: profile.telemetryUrl.port,
        deviceKey: '${profile.fingerprint}/${profile.phoneId}',
        phoneId: profile.phoneId,
        token: profile.token,
        caPem: profile.caPem,
      );

  final String host;
  final int port;
  final String deviceKey;
  final String phoneId;
  final String token;
  final String caPem;

  bool sameSession(TelemetryTarget other) =>
      deviceKey == other.deviceKey &&
      host == other.host &&
      port == other.port &&
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
        port: target.port,
        options: ChannelOptions(
          connectTimeout: const Duration(seconds: 6),
          credentials: ChannelCredentials.secure(
            certificates: utf8.encode(target.caPem),
          ),
        ),
      );

  final TelemetryTarget target;
  final ClientChannel _channel;
  TelemetryServiceClient get service => TelemetryServiceClient(_channel);
  CallOptions get unaryOptions => CallOptions(
    timeout: const Duration(seconds: 6),
    metadata: {'authorization': 'Bearer ${target.token}'},
  );

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
       _createTransport = createTransport ?? _GrpcTransport.new {
    if (Platform.isAndroid) {
      _background.setMethodCallHandler((call) async {
        if (call.method == 'stopped' && !_disposed) {
          _backgroundEnabled = false;
          if (!_foreground) {
            _endTransport();
            _phase = TelemetryPhase.stopped;
          }
          notifyListeners();
        }
      });
    }
  }

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
  bool _occupied = false;
  bool _backgroundEnabled = false;
  bool _defaultProfilePending = false;
  bool _applyingDefaultProfile = false;
  final _clock = Stopwatch()..start();
  int? _snapshotReceivedMs;
  Timer? _freshness;
  static const _background = MethodChannel('net.piagent.piagent/monitoring');
  final snapshotRevision = ValueNotifier<int>(0);

  MonitoringSnapshot? get snapshot => _snapshot;
  List<StoredTelemetryEvent> get messages => _messages;
  TelemetryPhase get phase => _phase;
  bool get storageError => _storageError;
  bool get isConfigured => _target != null;
  bool get isRequested => _requested;
  int get unreadCount => _messages.where((message) => message.unread).length;
  bool get supportsV2 => (_snapshot?.capabilityVersion ?? 0) >= 2;
  bool get supportsObservationMode =>
      _snapshot?.supportedFeatures.contains('observation_mode') ?? false;
  bool get occupied => _occupied;
  bool get backgroundEnabled => _backgroundEnabled;
  bool get applyingDefaultProfile => _applyingDefaultProfile;
  Duration? get snapshotAge => _snapshotReceivedMs == null
      ? null
      : Duration(
          milliseconds: _clock.elapsedMilliseconds - _snapshotReceivedMs!,
        );
  bool get stale =>
      snapshotAge == null || snapshotAge! >= const Duration(seconds: 7);

  Future<bool> setBackgroundReception(bool enable) async {
    if (!Platform.isAndroid || (enable && !_requested)) return false;
    try {
      final enabled =
          await _background.invokeMethod<bool>(enable ? 'start' : 'stop') ??
          false;
      if (_disposed) return false;
      _backgroundEnabled = enable && enabled;
      notifyListeners();
      return enable ? _backgroundEnabled : !_backgroundEnabled;
    } on PlatformException {
      return false;
    }
  }

  Future<ObservedDevicesPage> observedDevices({
    String? token,
    String? ssid,
    String? bssid,
  }) async {
    final transport = _transport;
    if (!supportsV2 || transport is! _GrpcTransport) {
      throw StateError('设备当前无法读取观测列表');
    }
    return transport.service.getObservedDevices(
      ObservedDevicesRequest(
        phoneId: transport.target.phoneId,
        pageToken: token,
        pageSize: 32,
        ssidFilter: ssid,
        bssidFilter: bssid,
      ),
      options: transport.unaryOptions,
    );
  }

  static String _requestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<ControlCommandResponse> setProfile(CaptureProfile value) async {
    _defaultProfilePending = false;
    return _requestProfile(value);
  }

  Future<ControlCommandResponse> setObservationPaused(bool paused) async {
    final transport = _transport;
    if (!supportsObservationMode || transport is! _GrpcTransport) {
      throw StateError('设备尚未提供监听切换');
    }
    return transport.service.setObservationMode(
      SetObservationModeRequest(
        phoneId: transport.target.phoneId,
        requestId: _requestId(),
        paused: paused,
      ),
      options: transport.unaryOptions,
    );
  }

  Future<ControlCommandResponse> _requestProfile(CaptureProfile value) async {
    final transport = _transport;
    if (!supportsV2 || transport is! _GrpcTransport) {
      throw StateError('设备尚未提供采集档位');
    }
    return transport.service.setCaptureProfile(
      SetCaptureProfileRequest(
        phoneId: transport.target.phoneId,
        requestId: _requestId(),
        targetProfile: value,
      ),
      options: transport.unaryOptions,
    );
  }

  Future<void> applyDefaultCaptureProfile() async {
    final snapshot = _snapshot;
    if (!_defaultProfilePending ||
        !_foreground ||
        _phase != TelemetryPhase.live ||
        stale ||
        !supportsV2 ||
        snapshot == null ||
        snapshot.capture.observationPauseRequested ||
        snapshot.capture.datasourceState == 'paused') {
      return;
    }
    final policy = snapshot.capturePolicy;
    if (policy.pressureForced ||
        snapshot.resourcePressure.level == ResourceLevel.LEVEL2_FALLBACK) {
      _defaultProfilePending = false;
      return;
    }
    if (policy.phase == 'switching' ||
        !const {'light', 'balanced', 'extended'}.contains(policy.actual)) {
      return;
    }
    _defaultProfilePending = false;
    if (policy.actual == 'extended') return;

    final generation = _generation;
    _applyingDefaultProfile = true;
    notifyListeners();
    try {
      if (!_isCurrent(generation)) return;
      await _requestProfile(CaptureProfile.EXTENDED);
    } catch (_) {
      // A later automatic stream retry is part of the same monitoring session.
    } finally {
      if (_isCurrent(generation)) {
        _applyingDefaultProfile = false;
        notifyListeners();
      }
    }
  }

  Future<ControlCommandResponse> recover(
    ComponentId component, {
    bool allowHotspotRestart = false,
  }) async {
    final transport = _transport;
    if (!supportsV2 || transport is! _GrpcTransport) {
      throw StateError('设备尚未提供组件恢复');
    }
    return transport.service.recoverComponent(
      RecoverComponentRequest(
        phoneId: transport.target.phoneId,
        requestId: _requestId(),
        component: component,
        allowHotspotRestart: allowHotspotRestart,
      ),
      options: transport.unaryOptions,
    );
  }

  Future<List<HighRiskRecord>> highRiskPage(int offset) async {
    final target = _target;
    return target == null
        ? const []
        : _repository.highRiskPage(target.deviceKey, offset);
  }

  Future<void> updateHighRisk(
    String id, {
    String? status,
    bool delete = false,
  }) async {
    final target = _target;
    if (target != null) {
      await _repository.updateHighRisk(
        target.deviceKey,
        id,
        status: status,
        delete: delete,
      );
    }
  }

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
    _snapshotReceivedMs = null;
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
    _occupied = false;
    if (_foreground || _backgroundEnabled) _connect();
  }

  void reconnect() {
    if (_target == null) return;
    _requested = true;
    _occupied = false;
    _connect();
  }

  void stop() {
    _requested = false;
    if (_backgroundEnabled) unawaited(setBackgroundReception(false));
    _endTransport();
    _phase = TelemetryPhase.stopped;
    notifyListeners();
  }

  void setForeground(bool foreground) {
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground && !_backgroundEnabled) {
      _endTransport();
      _phase = TelemetryPhase.stopped;
      notifyListeners();
    } else if (foreground && _requested && _stream == null && _retry == null) {
      _connect();
    }
  }

  void _connect() {
    final target = _target;
    if (target == null) return;
    _endTransport();
    _defaultProfilePending = true;
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
        acceptsHighRisk: transport is _GrpcTransport,
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
      _freshness = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isCurrent(generation) || _phase != TelemetryPhase.live) return;
        if (snapshotAge != null &&
            snapshotAge! >= const Duration(seconds: 12)) {
          _streamEnded(generation);
        } else {
          notifyListeners();
        }
      });
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
        if (previous != null &&
            previous.deviceBootId.isNotEmpty &&
            snapshot.deviceBootId.isNotEmpty &&
            previous.deviceBootId != snapshot.deviceBootId) {
          _defaultProfilePending = true;
        }
        if (_phase != TelemetryPhase.live ||
            previous == null ||
            previous.bootId != snapshot.bootId ||
            previous.sequence < snapshot.sequence) {
          _snapshot = snapshot;
          _snapshotReceivedMs = _clock.elapsedMilliseconds;
          snapshotRevision.value++;
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
      case TelemetryMessage_Payload.highRisk:
        await _saveAndAck(message.highRisk, target, generation);
      case TelemetryMessage_Payload.notSet:
        break;
    }
  }

  Future<void> _saveAndAck(
    HighRiskEnvelope envelope,
    TelemetryTarget target,
    int generation,
  ) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(envelope.durableId) ||
        envelope.event.eventCategory != EventCategory.SECURITY ||
        (envelope.event.riskClass != RiskClass.HIGH &&
            envelope.event.riskClass != RiskClass.CRITICAL)) {
      return;
    }
    final bool inserted;
    try {
      inserted = await _repository.ingestHighRisk(target.deviceKey, envelope);
    } catch (_) {
      if (_isCurrent(generation)) {
        _storageError = true;
        notifyListeners();
      }
      return;
    }
    if (!_isCurrent(generation)) return;
    _storageError = false;
    if (inserted) {
      _messages = List.unmodifiable([
        StoredTelemetryEvent(envelope.event, unread: true),
        ..._messages.take(_repository.maximumEvents - 1),
      ]);
    }
    if (inserted && Platform.isAndroid && _backgroundEnabled) {
      unawaited(
        _background
            .invokeMethod<void>('notifyRisk', {
              'id': envelope.durableId,
              'message': envelope.event.summary.isEmpty
                  ? '疑似高危无线行为'
                  : envelope.event.summary,
            })
            .catchError((Object _) {}),
      );
    }
    final transport = _transport;
    if (transport is _GrpcTransport) {
      try {
        await transport.service.ackHighRisk(
          AckHighRiskRequest(
            phoneId: target.phoneId,
            durableId: envelope.durableId,
          ),
          options: transport.unaryOptions,
        );
      } on GrpcError {
        // A later delivery retries ACK against the already committed archive entry.
      }
    }
    if (_isCurrent(generation)) notifyListeners();
  }

  Future<void> _store(
    TelemetryTarget target,
    int generation,
    MonitoringEvent event,
    EventCursor cursor,
  ) async {
    final bool inserted;
    try {
      if (supportsV2) {
        await _repository.saveCursor(target.deviceKey, cursor);
        inserted = !_messages.any(
          (item) => item.event.eventId == event.eventId,
        );
      } else {
        inserted = await _repository.ingest(target.deviceKey, event, cursor);
      }
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
    } else if (error is GrpcError &&
        error.code == StatusCode.resourceExhausted) {
      _phase = TelemetryPhase.stopped;
      _requested = false;
      _occupied = true;
    } else {
      _phase = TelemetryPhase.retrying;
      final target = _target!;
      final next = _generation;
      _retry = Timer(Duration(seconds: _backoffSeconds), () {
        _retry = null;
        _subscribe(target, next);
      });
      _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
    }
    notifyListeners();
  }

  void _endTransport() {
    _generation++;
    _applyingDefaultProfile = false;
    _retry?.cancel();
    _retry = null;
    _freshness?.cancel();
    _freshness = null;
    _stream?.cancel().ignore();
    _stream = null;
    _transport?.close().ignore();
    _transport = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _endTransport();
    snapshotRevision.dispose();
    if (Platform.isAndroid) _background.setMethodCallHandler(null);
    super.dispose();
  }
}
