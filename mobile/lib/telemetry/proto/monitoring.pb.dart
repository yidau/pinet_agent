// This is a generated file - do not edit.
//
// Generated from monitoring.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'monitoring.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'monitoring.pbenum.dart';

class SubscribeRequest extends $pb.GeneratedMessage {
  factory SubscribeRequest({
    $core.String? deviceId,
    $fixnum.Int64? lastEventSequence,
    $core.String? lastBootId,
    $core.bool? acceptsHighRisk,
  }) {
    final result = SubscribeRequest._();
    if (deviceId != null) result.deviceId = deviceId;
    if (lastEventSequence != null) result.lastEventSequence = lastEventSequence;
    if (lastBootId != null) result.lastBootId = lastBootId;
    if (acceptsHighRisk != null) result.acceptsHighRisk = acceptsHighRisk;
    return result;
  }

  SubscribeRequest._();

  factory SubscribeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SubscribeRequest()..mergeFromBuffer(data, registry);
  factory SubscribeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SubscribeRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SubscribeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: SubscribeRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'lastEventSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'lastBootId')
    ..aOB(4, _omitFieldNames ? '' : 'acceptsHighRisk')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SubscribeRequest copyWith(void Function(SubscribeRequest) updates) =>
      super.copyWith((message) => updates(message as SubscribeRequest))
          as SubscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SubscribeRequest() / SubscribeRequest.new instead')
  static SubscribeRequest create() => SubscribeRequest._();
  static $pb.GeneratedMessage $_createMessage() => SubscribeRequest._();
  @$core.override
  SubscribeRequest createEmptyInstance() => SubscribeRequest._();
  @$core.pragma('dart2js:noInline')
  static SubscribeRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SubscribeRequest>(
          SubscribeRequest.$_createMessage);
  static SubscribeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get lastEventSequence => $_getI64(1);
  @$pb.TagNumber(2)
  set lastEventSequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLastEventSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearLastEventSequence() => $_clearField(2);

  /// Replay epoch received in boot_id, opaque to clients.
  @$pb.TagNumber(3)
  $core.String get lastBootId => $_getSZ(2);
  @$pb.TagNumber(3)
  set lastBootId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLastBootId() => $_has(2);
  @$pb.TagNumber(3)
  void clearLastBootId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get acceptsHighRisk => $_getBF(3);
  @$pb.TagNumber(4)
  set acceptsHighRisk($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAcceptsHighRisk() => $_has(3);
  @$pb.TagNumber(4)
  void clearAcceptsHighRisk() => $_clearField(4);
}

enum TelemetryMessage_Payload { snapshot, event, historyGap, highRisk, notSet }

class TelemetryMessage extends $pb.GeneratedMessage {
  factory TelemetryMessage({
    MonitoringSnapshot? snapshot,
    MonitoringEvent? event,
    HistoryGap? historyGap,
    HighRiskEnvelope? highRisk,
  }) {
    final result = TelemetryMessage._();
    if (snapshot != null) result.snapshot = snapshot;
    if (event != null) result.event = event;
    if (historyGap != null) result.historyGap = historyGap;
    if (highRisk != null) result.highRisk = highRisk;
    return result;
  }

  TelemetryMessage._();

  factory TelemetryMessage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TelemetryMessage()..mergeFromBuffer(data, registry);
  factory TelemetryMessage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      TelemetryMessage()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, TelemetryMessage_Payload>
      _TelemetryMessage_PayloadByTag = {
    1: TelemetryMessage_Payload.snapshot,
    2: TelemetryMessage_Payload.event,
    3: TelemetryMessage_Payload.historyGap,
    4: TelemetryMessage_Payload.highRisk,
    0: TelemetryMessage_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TelemetryMessage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: TelemetryMessage.$_createMessage)
    ..oo(0, [1, 2, 3, 4])
    ..aOM<MonitoringSnapshot>(1, _omitFieldNames ? '' : 'snapshot',
        subBuilder: MonitoringSnapshot.$_createMessage)
    ..aOM<MonitoringEvent>(2, _omitFieldNames ? '' : 'event',
        subBuilder: MonitoringEvent.$_createMessage)
    ..aOM<HistoryGap>(3, _omitFieldNames ? '' : 'historyGap',
        subBuilder: HistoryGap.$_createMessage)
    ..aOM<HighRiskEnvelope>(4, _omitFieldNames ? '' : 'highRisk',
        subBuilder: HighRiskEnvelope.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TelemetryMessage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TelemetryMessage copyWith(void Function(TelemetryMessage) updates) =>
      super.copyWith((message) => updates(message as TelemetryMessage))
          as TelemetryMessage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use TelemetryMessage() / TelemetryMessage.new instead')
  static TelemetryMessage create() => TelemetryMessage._();
  static $pb.GeneratedMessage $_createMessage() => TelemetryMessage._();
  @$core.override
  TelemetryMessage createEmptyInstance() => TelemetryMessage._();
  @$core.pragma('dart2js:noInline')
  static TelemetryMessage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TelemetryMessage>(
          TelemetryMessage.$_createMessage);
  static TelemetryMessage? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  TelemetryMessage_Payload whichPayload() =>
      _TelemetryMessage_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  MonitoringSnapshot get snapshot => $_getN(0);
  @$pb.TagNumber(1)
  set snapshot(MonitoringSnapshot value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshot() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshot() => $_clearField(1);
  @$pb.TagNumber(1)
  MonitoringSnapshot ensureSnapshot() => $_ensure(0);

  @$pb.TagNumber(2)
  MonitoringEvent get event => $_getN(1);
  @$pb.TagNumber(2)
  set event(MonitoringEvent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEvent() => $_has(1);
  @$pb.TagNumber(2)
  void clearEvent() => $_clearField(2);
  @$pb.TagNumber(2)
  MonitoringEvent ensureEvent() => $_ensure(1);

  @$pb.TagNumber(3)
  HistoryGap get historyGap => $_getN(2);
  @$pb.TagNumber(3)
  set historyGap(HistoryGap value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasHistoryGap() => $_has(2);
  @$pb.TagNumber(3)
  void clearHistoryGap() => $_clearField(3);
  @$pb.TagNumber(3)
  HistoryGap ensureHistoryGap() => $_ensure(2);

  @$pb.TagNumber(4)
  HighRiskEnvelope get highRisk => $_getN(3);
  @$pb.TagNumber(4)
  set highRisk(HighRiskEnvelope value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasHighRisk() => $_has(3);
  @$pb.TagNumber(4)
  void clearHighRisk() => $_clearField(4);
  @$pb.TagNumber(4)
  HighRiskEnvelope ensureHighRisk() => $_ensure(3);
}

class HistoryGap extends $pb.GeneratedMessage {
  factory HistoryGap({
    $core.String? bootId,
    $fixnum.Int64? throughEventSequence,
    $core.String? reason,
  }) {
    final result = HistoryGap._();
    if (bootId != null) result.bootId = bootId;
    if (throughEventSequence != null)
      result.throughEventSequence = throughEventSequence;
    if (reason != null) result.reason = reason;
    return result;
  }

  HistoryGap._();

  factory HistoryGap.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HistoryGap()..mergeFromBuffer(data, registry);
  factory HistoryGap.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HistoryGap()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HistoryGap',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: HistoryGap.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'bootId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'throughEventSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HistoryGap clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HistoryGap copyWith(void Function(HistoryGap) updates) =>
      super.copyWith((message) => updates(message as HistoryGap)) as HistoryGap;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HistoryGap() / HistoryGap.new instead')
  static HistoryGap create() => HistoryGap._();
  static $pb.GeneratedMessage $_createMessage() => HistoryGap._();
  @$core.override
  HistoryGap createEmptyInstance() => HistoryGap._();
  @$core.pragma('dart2js:noInline')
  static HistoryGap getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HistoryGap>(HistoryGap.$_createMessage);
  static HistoryGap? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get bootId => $_getSZ(0);
  @$pb.TagNumber(1)
  set bootId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBootId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBootId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get throughEventSequence => $_getI64(1);
  @$pb.TagNumber(2)
  set throughEventSequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasThroughEventSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearThroughEventSequence() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get reason => $_getSZ(2);
  @$pb.TagNumber(3)
  set reason($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearReason() => $_clearField(3);
}

class MonitoringSnapshot extends $pb.GeneratedMessage {
  factory MonitoringSnapshot({
    $core.String? bootId,
    $fixnum.Int64? sequence,
    $fixnum.Int64? timestampMs,
    SystemMetrics? system,
    CaptureMetrics? capture,
    WirelessSummary? wireless,
    $core.int? schemaVersion,
    $fixnum.Int64? latestEventSequence,
    DeliveryMetrics? delivery,
    DeviceHealth? deviceHealth,
    CapturePolicyStatus? capturePolicy,
    ObservationSession? observationSession,
    HighRiskDeliveryStatus? highRiskDelivery,
    $core.int? capabilityVersion,
    $core.Iterable<$core.String>? supportedFeatures,
    $core.String? deviceBootId,
    ResourcePressureStatus? resourcePressure,
  }) {
    final result = MonitoringSnapshot._();
    if (bootId != null) result.bootId = bootId;
    if (sequence != null) result.sequence = sequence;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (system != null) result.system = system;
    if (capture != null) result.capture = capture;
    if (wireless != null) result.wireless = wireless;
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (latestEventSequence != null)
      result.latestEventSequence = latestEventSequence;
    if (delivery != null) result.delivery = delivery;
    if (deviceHealth != null) result.deviceHealth = deviceHealth;
    if (capturePolicy != null) result.capturePolicy = capturePolicy;
    if (observationSession != null)
      result.observationSession = observationSession;
    if (highRiskDelivery != null) result.highRiskDelivery = highRiskDelivery;
    if (capabilityVersion != null) result.capabilityVersion = capabilityVersion;
    if (supportedFeatures != null)
      result.supportedFeatures.addAll(supportedFeatures);
    if (deviceBootId != null) result.deviceBootId = deviceBootId;
    if (resourcePressure != null) result.resourcePressure = resourcePressure;
    return result;
  }

  MonitoringSnapshot._();

  factory MonitoringSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MonitoringSnapshot()..mergeFromBuffer(data, registry);
  factory MonitoringSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MonitoringSnapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MonitoringSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: MonitoringSnapshot.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'bootId')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..aOM<SystemMetrics>(4, _omitFieldNames ? '' : 'system',
        subBuilder: SystemMetrics.$_createMessage)
    ..aOM<CaptureMetrics>(5, _omitFieldNames ? '' : 'capture',
        subBuilder: CaptureMetrics.$_createMessage)
    ..aOM<WirelessSummary>(6, _omitFieldNames ? '' : 'wireless',
        subBuilder: WirelessSummary.$_createMessage)
    ..aI(7, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'latestEventSequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<DeliveryMetrics>(9, _omitFieldNames ? '' : 'delivery',
        subBuilder: DeliveryMetrics.$_createMessage)
    ..aOM<DeviceHealth>(10, _omitFieldNames ? '' : 'deviceHealth',
        subBuilder: DeviceHealth.$_createMessage)
    ..aOM<CapturePolicyStatus>(11, _omitFieldNames ? '' : 'capturePolicy',
        subBuilder: CapturePolicyStatus.$_createMessage)
    ..aOM<ObservationSession>(12, _omitFieldNames ? '' : 'observationSession',
        subBuilder: ObservationSession.$_createMessage)
    ..aOM<HighRiskDeliveryStatus>(13, _omitFieldNames ? '' : 'highRiskDelivery',
        subBuilder: HighRiskDeliveryStatus.$_createMessage)
    ..aI(14, _omitFieldNames ? '' : 'capabilityVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..pPS(15, _omitFieldNames ? '' : 'supportedFeatures')
    ..aOS(16, _omitFieldNames ? '' : 'deviceBootId')
    ..aOM<ResourcePressureStatus>(17, _omitFieldNames ? '' : 'resourcePressure',
        subBuilder: ResourcePressureStatus.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MonitoringSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MonitoringSnapshot copyWith(void Function(MonitoringSnapshot) updates) =>
      super.copyWith((message) => updates(message as MonitoringSnapshot))
          as MonitoringSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MonitoringSnapshot() / MonitoringSnapshot.new instead')
  static MonitoringSnapshot create() => MonitoringSnapshot._();
  static $pb.GeneratedMessage $_createMessage() => MonitoringSnapshot._();
  @$core.override
  MonitoringSnapshot createEmptyInstance() => MonitoringSnapshot._();
  @$core.pragma('dart2js:noInline')
  static MonitoringSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MonitoringSnapshot>(
          MonitoringSnapshot.$_createMessage);
  static MonitoringSnapshot? _defaultInstance;

  /// Replay epoch: Linux boot identifier followed by a per-process identifier.
  @$pb.TagNumber(1)
  $core.String get bootId => $_getSZ(0);
  @$pb.TagNumber(1)
  set bootId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBootId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBootId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sequence => $_getI64(1);
  @$pb.TagNumber(2)
  set sequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequence() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => $_clearField(3);

  @$pb.TagNumber(4)
  SystemMetrics get system => $_getN(3);
  @$pb.TagNumber(4)
  set system(SystemMetrics value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasSystem() => $_has(3);
  @$pb.TagNumber(4)
  void clearSystem() => $_clearField(4);
  @$pb.TagNumber(4)
  SystemMetrics ensureSystem() => $_ensure(3);

  @$pb.TagNumber(5)
  CaptureMetrics get capture => $_getN(4);
  @$pb.TagNumber(5)
  set capture(CaptureMetrics value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasCapture() => $_has(4);
  @$pb.TagNumber(5)
  void clearCapture() => $_clearField(5);
  @$pb.TagNumber(5)
  CaptureMetrics ensureCapture() => $_ensure(4);

  @$pb.TagNumber(6)
  WirelessSummary get wireless => $_getN(5);
  @$pb.TagNumber(6)
  set wireless(WirelessSummary value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasWireless() => $_has(5);
  @$pb.TagNumber(6)
  void clearWireless() => $_clearField(6);
  @$pb.TagNumber(6)
  WirelessSummary ensureWireless() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.int get schemaVersion => $_getIZ(6);
  @$pb.TagNumber(7)
  set schemaVersion($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSchemaVersion() => $_has(6);
  @$pb.TagNumber(7)
  void clearSchemaVersion() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get latestEventSequence => $_getI64(7);
  @$pb.TagNumber(8)
  set latestEventSequence($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLatestEventSequence() => $_has(7);
  @$pb.TagNumber(8)
  void clearLatestEventSequence() => $_clearField(8);

  @$pb.TagNumber(9)
  DeliveryMetrics get delivery => $_getN(8);
  @$pb.TagNumber(9)
  set delivery(DeliveryMetrics value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasDelivery() => $_has(8);
  @$pb.TagNumber(9)
  void clearDelivery() => $_clearField(9);
  @$pb.TagNumber(9)
  DeliveryMetrics ensureDelivery() => $_ensure(8);

  @$pb.TagNumber(10)
  DeviceHealth get deviceHealth => $_getN(9);
  @$pb.TagNumber(10)
  set deviceHealth(DeviceHealth value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasDeviceHealth() => $_has(9);
  @$pb.TagNumber(10)
  void clearDeviceHealth() => $_clearField(10);
  @$pb.TagNumber(10)
  DeviceHealth ensureDeviceHealth() => $_ensure(9);

  @$pb.TagNumber(11)
  CapturePolicyStatus get capturePolicy => $_getN(10);
  @$pb.TagNumber(11)
  set capturePolicy(CapturePolicyStatus value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasCapturePolicy() => $_has(10);
  @$pb.TagNumber(11)
  void clearCapturePolicy() => $_clearField(11);
  @$pb.TagNumber(11)
  CapturePolicyStatus ensureCapturePolicy() => $_ensure(10);

  @$pb.TagNumber(12)
  ObservationSession get observationSession => $_getN(11);
  @$pb.TagNumber(12)
  set observationSession(ObservationSession value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasObservationSession() => $_has(11);
  @$pb.TagNumber(12)
  void clearObservationSession() => $_clearField(12);
  @$pb.TagNumber(12)
  ObservationSession ensureObservationSession() => $_ensure(11);

  @$pb.TagNumber(13)
  HighRiskDeliveryStatus get highRiskDelivery => $_getN(12);
  @$pb.TagNumber(13)
  set highRiskDelivery(HighRiskDeliveryStatus value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasHighRiskDelivery() => $_has(12);
  @$pb.TagNumber(13)
  void clearHighRiskDelivery() => $_clearField(13);
  @$pb.TagNumber(13)
  HighRiskDeliveryStatus ensureHighRiskDelivery() => $_ensure(12);

  @$pb.TagNumber(14)
  $core.int get capabilityVersion => $_getIZ(13);
  @$pb.TagNumber(14)
  set capabilityVersion($core.int value) => $_setUnsignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasCapabilityVersion() => $_has(13);
  @$pb.TagNumber(14)
  void clearCapabilityVersion() => $_clearField(14);

  @$pb.TagNumber(15)
  $pb.PbList<$core.String> get supportedFeatures => $_getList(14);

  @$pb.TagNumber(16)
  $core.String get deviceBootId => $_getSZ(15);
  @$pb.TagNumber(16)
  set deviceBootId($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasDeviceBootId() => $_has(15);
  @$pb.TagNumber(16)
  void clearDeviceBootId() => $_clearField(16);

  @$pb.TagNumber(17)
  ResourcePressureStatus get resourcePressure => $_getN(16);
  @$pb.TagNumber(17)
  set resourcePressure(ResourcePressureStatus value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasResourcePressure() => $_has(16);
  @$pb.TagNumber(17)
  void clearResourcePressure() => $_clearField(17);
  @$pb.TagNumber(17)
  ResourcePressureStatus ensureResourcePressure() => $_ensure(16);
}

class SystemMetrics extends $pb.GeneratedMessage {
  factory SystemMetrics({
    $core.double? cpuUsage,
    $fixnum.Int64? memoryTotalBytes,
    $fixnum.Int64? memoryAvailableBytes,
    $core.double? temperatureC,
    $core.double? cpuPsiSomeAvg10,
    $core.double? memoryPsiSomeAvg10,
    $fixnum.Int64? swapTotalBytes,
    $fixnum.Int64? swapFreeBytes,
    $core.double? cpuFrequencyMhz,
    $core.double? diskReadBytesPerSecond,
    $core.double? diskWriteBytesPerSecond,
    $core.double? diskReadsPerSecond,
    $core.double? diskWritesPerSecond,
    $core.double? diskBusyMsPerSecond,
    Pressure? cpuPressure,
    Pressure? memoryPressure,
    Pressure? ioPressure,
    $fixnum.Int64? sampledAtMs,
    $fixnum.Int64? memoryUsedBytes,
  }) {
    final result = SystemMetrics._();
    if (cpuUsage != null) result.cpuUsage = cpuUsage;
    if (memoryTotalBytes != null) result.memoryTotalBytes = memoryTotalBytes;
    if (memoryAvailableBytes != null)
      result.memoryAvailableBytes = memoryAvailableBytes;
    if (temperatureC != null) result.temperatureC = temperatureC;
    if (cpuPsiSomeAvg10 != null) result.cpuPsiSomeAvg10 = cpuPsiSomeAvg10;
    if (memoryPsiSomeAvg10 != null)
      result.memoryPsiSomeAvg10 = memoryPsiSomeAvg10;
    if (swapTotalBytes != null) result.swapTotalBytes = swapTotalBytes;
    if (swapFreeBytes != null) result.swapFreeBytes = swapFreeBytes;
    if (cpuFrequencyMhz != null) result.cpuFrequencyMhz = cpuFrequencyMhz;
    if (diskReadBytesPerSecond != null)
      result.diskReadBytesPerSecond = diskReadBytesPerSecond;
    if (diskWriteBytesPerSecond != null)
      result.diskWriteBytesPerSecond = diskWriteBytesPerSecond;
    if (diskReadsPerSecond != null)
      result.diskReadsPerSecond = diskReadsPerSecond;
    if (diskWritesPerSecond != null)
      result.diskWritesPerSecond = diskWritesPerSecond;
    if (diskBusyMsPerSecond != null)
      result.diskBusyMsPerSecond = diskBusyMsPerSecond;
    if (cpuPressure != null) result.cpuPressure = cpuPressure;
    if (memoryPressure != null) result.memoryPressure = memoryPressure;
    if (ioPressure != null) result.ioPressure = ioPressure;
    if (sampledAtMs != null) result.sampledAtMs = sampledAtMs;
    if (memoryUsedBytes != null) result.memoryUsedBytes = memoryUsedBytes;
    return result;
  }

  SystemMetrics._();

  factory SystemMetrics.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SystemMetrics()..mergeFromBuffer(data, registry);
  factory SystemMetrics.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SystemMetrics()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SystemMetrics',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: SystemMetrics.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'cpuUsage', fieldType: $pb.PbFieldType.OF)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'memoryTotalBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'memoryAvailableBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(4, _omitFieldNames ? '' : 'temperatureC',
        fieldType: $pb.PbFieldType.OF)
    ..aD(5, _omitFieldNames ? '' : 'cpuPsiSomeAvg10',
        fieldType: $pb.PbFieldType.OF)
    ..aD(6, _omitFieldNames ? '' : 'memoryPsiSomeAvg10',
        fieldType: $pb.PbFieldType.OF)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'swapTotalBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'swapFreeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(9, _omitFieldNames ? '' : 'cpuFrequencyMhz',
        fieldType: $pb.PbFieldType.OF)
    ..aD(10, _omitFieldNames ? '' : 'diskReadBytesPerSecond')
    ..aD(11, _omitFieldNames ? '' : 'diskWriteBytesPerSecond')
    ..aD(12, _omitFieldNames ? '' : 'diskReadsPerSecond')
    ..aD(13, _omitFieldNames ? '' : 'diskWritesPerSecond')
    ..aD(14, _omitFieldNames ? '' : 'diskBusyMsPerSecond')
    ..aOM<Pressure>(15, _omitFieldNames ? '' : 'cpuPressure',
        subBuilder: Pressure.$_createMessage)
    ..aOM<Pressure>(16, _omitFieldNames ? '' : 'memoryPressure',
        subBuilder: Pressure.$_createMessage)
    ..aOM<Pressure>(17, _omitFieldNames ? '' : 'ioPressure',
        subBuilder: Pressure.$_createMessage)
    ..aInt64(18, _omitFieldNames ? '' : 'sampledAtMs')
    ..a<$fixnum.Int64>(
        19, _omitFieldNames ? '' : 'memoryUsedBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SystemMetrics clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SystemMetrics copyWith(void Function(SystemMetrics) updates) =>
      super.copyWith((message) => updates(message as SystemMetrics))
          as SystemMetrics;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SystemMetrics() / SystemMetrics.new instead')
  static SystemMetrics create() => SystemMetrics._();
  static $pb.GeneratedMessage $_createMessage() => SystemMetrics._();
  @$core.override
  SystemMetrics createEmptyInstance() => SystemMetrics._();
  @$core.pragma('dart2js:noInline')
  static SystemMetrics getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SystemMetrics>(
          SystemMetrics.$_createMessage);
  static SystemMetrics? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get cpuUsage => $_getN(0);
  @$pb.TagNumber(1)
  set cpuUsage($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCpuUsage() => $_has(0);
  @$pb.TagNumber(1)
  void clearCpuUsage() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get memoryTotalBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set memoryTotalBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMemoryTotalBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryTotalBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get memoryAvailableBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set memoryAvailableBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMemoryAvailableBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearMemoryAvailableBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get temperatureC => $_getN(3);
  @$pb.TagNumber(4)
  set temperatureC($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTemperatureC() => $_has(3);
  @$pb.TagNumber(4)
  void clearTemperatureC() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get cpuPsiSomeAvg10 => $_getN(4);
  @$pb.TagNumber(5)
  set cpuPsiSomeAvg10($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCpuPsiSomeAvg10() => $_has(4);
  @$pb.TagNumber(5)
  void clearCpuPsiSomeAvg10() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get memoryPsiSomeAvg10 => $_getN(5);
  @$pb.TagNumber(6)
  set memoryPsiSomeAvg10($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasMemoryPsiSomeAvg10() => $_has(5);
  @$pb.TagNumber(6)
  void clearMemoryPsiSomeAvg10() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get swapTotalBytes => $_getI64(6);
  @$pb.TagNumber(7)
  set swapTotalBytes($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSwapTotalBytes() => $_has(6);
  @$pb.TagNumber(7)
  void clearSwapTotalBytes() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get swapFreeBytes => $_getI64(7);
  @$pb.TagNumber(8)
  set swapFreeBytes($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSwapFreeBytes() => $_has(7);
  @$pb.TagNumber(8)
  void clearSwapFreeBytes() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get cpuFrequencyMhz => $_getN(8);
  @$pb.TagNumber(9)
  set cpuFrequencyMhz($core.double value) => $_setFloat(8, value);
  @$pb.TagNumber(9)
  $core.bool hasCpuFrequencyMhz() => $_has(8);
  @$pb.TagNumber(9)
  void clearCpuFrequencyMhz() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.double get diskReadBytesPerSecond => $_getN(9);
  @$pb.TagNumber(10)
  set diskReadBytesPerSecond($core.double value) => $_setDouble(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDiskReadBytesPerSecond() => $_has(9);
  @$pb.TagNumber(10)
  void clearDiskReadBytesPerSecond() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.double get diskWriteBytesPerSecond => $_getN(10);
  @$pb.TagNumber(11)
  set diskWriteBytesPerSecond($core.double value) => $_setDouble(10, value);
  @$pb.TagNumber(11)
  $core.bool hasDiskWriteBytesPerSecond() => $_has(10);
  @$pb.TagNumber(11)
  void clearDiskWriteBytesPerSecond() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.double get diskReadsPerSecond => $_getN(11);
  @$pb.TagNumber(12)
  set diskReadsPerSecond($core.double value) => $_setDouble(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDiskReadsPerSecond() => $_has(11);
  @$pb.TagNumber(12)
  void clearDiskReadsPerSecond() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.double get diskWritesPerSecond => $_getN(12);
  @$pb.TagNumber(13)
  set diskWritesPerSecond($core.double value) => $_setDouble(12, value);
  @$pb.TagNumber(13)
  $core.bool hasDiskWritesPerSecond() => $_has(12);
  @$pb.TagNumber(13)
  void clearDiskWritesPerSecond() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.double get diskBusyMsPerSecond => $_getN(13);
  @$pb.TagNumber(14)
  set diskBusyMsPerSecond($core.double value) => $_setDouble(13, value);
  @$pb.TagNumber(14)
  $core.bool hasDiskBusyMsPerSecond() => $_has(13);
  @$pb.TagNumber(14)
  void clearDiskBusyMsPerSecond() => $_clearField(14);

  @$pb.TagNumber(15)
  Pressure get cpuPressure => $_getN(14);
  @$pb.TagNumber(15)
  set cpuPressure(Pressure value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasCpuPressure() => $_has(14);
  @$pb.TagNumber(15)
  void clearCpuPressure() => $_clearField(15);
  @$pb.TagNumber(15)
  Pressure ensureCpuPressure() => $_ensure(14);

  @$pb.TagNumber(16)
  Pressure get memoryPressure => $_getN(15);
  @$pb.TagNumber(16)
  set memoryPressure(Pressure value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasMemoryPressure() => $_has(15);
  @$pb.TagNumber(16)
  void clearMemoryPressure() => $_clearField(16);
  @$pb.TagNumber(16)
  Pressure ensureMemoryPressure() => $_ensure(15);

  @$pb.TagNumber(17)
  Pressure get ioPressure => $_getN(16);
  @$pb.TagNumber(17)
  set ioPressure(Pressure value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasIoPressure() => $_has(16);
  @$pb.TagNumber(17)
  void clearIoPressure() => $_clearField(17);
  @$pb.TagNumber(17)
  Pressure ensureIoPressure() => $_ensure(16);

  @$pb.TagNumber(18)
  $fixnum.Int64 get sampledAtMs => $_getI64(17);
  @$pb.TagNumber(18)
  set sampledAtMs($fixnum.Int64 value) => $_setInt64(17, value);
  @$pb.TagNumber(18)
  $core.bool hasSampledAtMs() => $_has(17);
  @$pb.TagNumber(18)
  void clearSampledAtMs() => $_clearField(18);

  @$pb.TagNumber(19)
  $fixnum.Int64 get memoryUsedBytes => $_getI64(18);
  @$pb.TagNumber(19)
  set memoryUsedBytes($fixnum.Int64 value) => $_setInt64(18, value);
  @$pb.TagNumber(19)
  $core.bool hasMemoryUsedBytes() => $_has(18);
  @$pb.TagNumber(19)
  void clearMemoryUsedBytes() => $_clearField(19);
}

class Pressure extends $pb.GeneratedMessage {
  factory Pressure({
    $core.double? someAvg10,
    $core.double? someAvg60,
    $core.double? fullAvg10,
    $core.double? fullAvg60,
  }) {
    final result = Pressure._();
    if (someAvg10 != null) result.someAvg10 = someAvg10;
    if (someAvg60 != null) result.someAvg60 = someAvg60;
    if (fullAvg10 != null) result.fullAvg10 = fullAvg10;
    if (fullAvg60 != null) result.fullAvg60 = fullAvg60;
    return result;
  }

  Pressure._();

  factory Pressure.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pressure()..mergeFromBuffer(data, registry);
  factory Pressure.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Pressure()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Pressure',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: Pressure.$_createMessage)
    ..aD(1, _omitFieldNames ? '' : 'someAvg10', fieldType: $pb.PbFieldType.OF)
    ..aD(2, _omitFieldNames ? '' : 'someAvg60', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'fullAvg10', fieldType: $pb.PbFieldType.OF)
    ..aD(4, _omitFieldNames ? '' : 'fullAvg60', fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pressure clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Pressure copyWith(void Function(Pressure) updates) =>
      super.copyWith((message) => updates(message as Pressure)) as Pressure;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Pressure() / Pressure.new instead')
  static Pressure create() => Pressure._();
  static $pb.GeneratedMessage $_createMessage() => Pressure._();
  @$core.override
  Pressure createEmptyInstance() => Pressure._();
  @$core.pragma('dart2js:noInline')
  static Pressure getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Pressure>(Pressure.$_createMessage);
  static Pressure? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get someAvg10 => $_getN(0);
  @$pb.TagNumber(1)
  set someAvg10($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSomeAvg10() => $_has(0);
  @$pb.TagNumber(1)
  void clearSomeAvg10() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get someAvg60 => $_getN(1);
  @$pb.TagNumber(2)
  set someAvg60($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSomeAvg60() => $_has(1);
  @$pb.TagNumber(2)
  void clearSomeAvg60() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get fullAvg10 => $_getN(2);
  @$pb.TagNumber(3)
  set fullAvg10($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFullAvg10() => $_has(2);
  @$pb.TagNumber(3)
  void clearFullAvg10() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get fullAvg60 => $_getN(3);
  @$pb.TagNumber(4)
  set fullAvg60($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFullAvg60() => $_has(3);
  @$pb.TagNumber(4)
  void clearFullAvg60() => $_clearField(4);
}

class CaptureMetrics extends $pb.GeneratedMessage {
  factory CaptureMetrics({
    $core.bool? kismetRunning,
    $core.bool? datasourceRunning,
    $core.String? datasourceState,
    $fixnum.Int64? packetsPerSecond,
    $fixnum.Int64? processedPacketsPerSecond,
    $fixnum.Int64? backlog,
    $fixnum.Int64? droppedPackets,
    $core.String? coverage,
    $fixnum.Int64? sampledAtMs,
    $core.String? reason,
    $core.String? currentChannel,
    $core.bool? datasourcePaused,
    $core.bool? datasourceError,
    $fixnum.Int64? trackedDevices,
    $core.String? packetStatisticsSource,
    $core.String? datasourceUuid,
  }) {
    final result = CaptureMetrics._();
    if (kismetRunning != null) result.kismetRunning = kismetRunning;
    if (datasourceRunning != null) result.datasourceRunning = datasourceRunning;
    if (datasourceState != null) result.datasourceState = datasourceState;
    if (packetsPerSecond != null) result.packetsPerSecond = packetsPerSecond;
    if (processedPacketsPerSecond != null)
      result.processedPacketsPerSecond = processedPacketsPerSecond;
    if (backlog != null) result.backlog = backlog;
    if (droppedPackets != null) result.droppedPackets = droppedPackets;
    if (coverage != null) result.coverage = coverage;
    if (sampledAtMs != null) result.sampledAtMs = sampledAtMs;
    if (reason != null) result.reason = reason;
    if (currentChannel != null) result.currentChannel = currentChannel;
    if (datasourcePaused != null) result.datasourcePaused = datasourcePaused;
    if (datasourceError != null) result.datasourceError = datasourceError;
    if (trackedDevices != null) result.trackedDevices = trackedDevices;
    if (packetStatisticsSource != null)
      result.packetStatisticsSource = packetStatisticsSource;
    if (datasourceUuid != null) result.datasourceUuid = datasourceUuid;
    return result;
  }

  CaptureMetrics._();

  factory CaptureMetrics.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CaptureMetrics()..mergeFromBuffer(data, registry);
  factory CaptureMetrics.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CaptureMetrics()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CaptureMetrics',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: CaptureMetrics.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'kismetRunning')
    ..aOB(2, _omitFieldNames ? '' : 'datasourceRunning')
    ..aOS(3, _omitFieldNames ? '' : 'datasourceState')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'packetsPerSecond', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'processedPacketsPerSecond',
        $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(6, _omitFieldNames ? '' : 'backlog', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'droppedPackets', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(8, _omitFieldNames ? '' : 'coverage')
    ..aInt64(9, _omitFieldNames ? '' : 'sampledAtMs')
    ..aOS(10, _omitFieldNames ? '' : 'reason')
    ..aOS(11, _omitFieldNames ? '' : 'currentChannel')
    ..aOB(12, _omitFieldNames ? '' : 'datasourcePaused')
    ..aOB(13, _omitFieldNames ? '' : 'datasourceError')
    ..a<$fixnum.Int64>(
        14, _omitFieldNames ? '' : 'trackedDevices', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(15, _omitFieldNames ? '' : 'packetStatisticsSource')
    ..aOS(16, _omitFieldNames ? '' : 'datasourceUuid')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CaptureMetrics clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CaptureMetrics copyWith(void Function(CaptureMetrics) updates) =>
      super.copyWith((message) => updates(message as CaptureMetrics))
          as CaptureMetrics;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CaptureMetrics() / CaptureMetrics.new instead')
  static CaptureMetrics create() => CaptureMetrics._();
  static $pb.GeneratedMessage $_createMessage() => CaptureMetrics._();
  @$core.override
  CaptureMetrics createEmptyInstance() => CaptureMetrics._();
  @$core.pragma('dart2js:noInline')
  static CaptureMetrics getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CaptureMetrics>(
          CaptureMetrics.$_createMessage);
  static CaptureMetrics? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get kismetRunning => $_getBF(0);
  @$pb.TagNumber(1)
  set kismetRunning($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKismetRunning() => $_has(0);
  @$pb.TagNumber(1)
  void clearKismetRunning() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get datasourceRunning => $_getBF(1);
  @$pb.TagNumber(2)
  set datasourceRunning($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDatasourceRunning() => $_has(1);
  @$pb.TagNumber(2)
  void clearDatasourceRunning() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get datasourceState => $_getSZ(2);
  @$pb.TagNumber(3)
  set datasourceState($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDatasourceState() => $_has(2);
  @$pb.TagNumber(3)
  void clearDatasourceState() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get packetsPerSecond => $_getI64(3);
  @$pb.TagNumber(4)
  set packetsPerSecond($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPacketsPerSecond() => $_has(3);
  @$pb.TagNumber(4)
  void clearPacketsPerSecond() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get processedPacketsPerSecond => $_getI64(4);
  @$pb.TagNumber(5)
  set processedPacketsPerSecond($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasProcessedPacketsPerSecond() => $_has(4);
  @$pb.TagNumber(5)
  void clearProcessedPacketsPerSecond() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get backlog => $_getI64(5);
  @$pb.TagNumber(6)
  set backlog($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasBacklog() => $_has(5);
  @$pb.TagNumber(6)
  void clearBacklog() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get droppedPackets => $_getI64(6);
  @$pb.TagNumber(7)
  set droppedPackets($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDroppedPackets() => $_has(6);
  @$pb.TagNumber(7)
  void clearDroppedPackets() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get coverage => $_getSZ(7);
  @$pb.TagNumber(8)
  set coverage($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCoverage() => $_has(7);
  @$pb.TagNumber(8)
  void clearCoverage() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get sampledAtMs => $_getI64(8);
  @$pb.TagNumber(9)
  set sampledAtMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSampledAtMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearSampledAtMs() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get reason => $_getSZ(9);
  @$pb.TagNumber(10)
  set reason($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasReason() => $_has(9);
  @$pb.TagNumber(10)
  void clearReason() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get currentChannel => $_getSZ(10);
  @$pb.TagNumber(11)
  set currentChannel($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasCurrentChannel() => $_has(10);
  @$pb.TagNumber(11)
  void clearCurrentChannel() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.bool get datasourcePaused => $_getBF(11);
  @$pb.TagNumber(12)
  set datasourcePaused($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDatasourcePaused() => $_has(11);
  @$pb.TagNumber(12)
  void clearDatasourcePaused() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get datasourceError => $_getBF(12);
  @$pb.TagNumber(13)
  set datasourceError($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasDatasourceError() => $_has(12);
  @$pb.TagNumber(13)
  void clearDatasourceError() => $_clearField(13);

  @$pb.TagNumber(14)
  $fixnum.Int64 get trackedDevices => $_getI64(13);
  @$pb.TagNumber(14)
  set trackedDevices($fixnum.Int64 value) => $_setInt64(13, value);
  @$pb.TagNumber(14)
  $core.bool hasTrackedDevices() => $_has(13);
  @$pb.TagNumber(14)
  void clearTrackedDevices() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get packetStatisticsSource => $_getSZ(14);
  @$pb.TagNumber(15)
  set packetStatisticsSource($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasPacketStatisticsSource() => $_has(14);
  @$pb.TagNumber(15)
  void clearPacketStatisticsSource() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get datasourceUuid => $_getSZ(15);
  @$pb.TagNumber(16)
  set datasourceUuid($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasDatasourceUuid() => $_has(15);
  @$pb.TagNumber(16)
  void clearDatasourceUuid() => $_clearField(16);
}

class WirelessSummary extends $pb.GeneratedMessage {
  factory WirelessSummary({
    $core.int? apCount,
    $core.int? clientCount,
    $core.Iterable<PriorityAP>? priorityAps,
    $core.bool? truncated,
    $fixnum.Int64? sampledAtMs,
    $core.String? coverage,
  }) {
    final result = WirelessSummary._();
    if (apCount != null) result.apCount = apCount;
    if (clientCount != null) result.clientCount = clientCount;
    if (priorityAps != null) result.priorityAps.addAll(priorityAps);
    if (truncated != null) result.truncated = truncated;
    if (sampledAtMs != null) result.sampledAtMs = sampledAtMs;
    if (coverage != null) result.coverage = coverage;
    return result;
  }

  WirelessSummary._();

  factory WirelessSummary.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WirelessSummary()..mergeFromBuffer(data, registry);
  factory WirelessSummary.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WirelessSummary()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WirelessSummary',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: WirelessSummary.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'apCount', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'clientCount',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<PriorityAP>(3, _omitFieldNames ? '' : 'priorityAps',
        subBuilder: PriorityAP.$_createMessage)
    ..aOB(4, _omitFieldNames ? '' : 'truncated')
    ..aInt64(5, _omitFieldNames ? '' : 'sampledAtMs')
    ..aOS(6, _omitFieldNames ? '' : 'coverage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WirelessSummary clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WirelessSummary copyWith(void Function(WirelessSummary) updates) =>
      super.copyWith((message) => updates(message as WirelessSummary))
          as WirelessSummary;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WirelessSummary() / WirelessSummary.new instead')
  static WirelessSummary create() => WirelessSummary._();
  static $pb.GeneratedMessage $_createMessage() => WirelessSummary._();
  @$core.override
  WirelessSummary createEmptyInstance() => WirelessSummary._();
  @$core.pragma('dart2js:noInline')
  static WirelessSummary getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WirelessSummary>(
          WirelessSummary.$_createMessage);
  static WirelessSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get apCount => $_getIZ(0);
  @$pb.TagNumber(1)
  set apCount($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasApCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearApCount() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get clientCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set clientCount($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClientCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearClientCount() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<PriorityAP> get priorityAps => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get truncated => $_getBF(3);
  @$pb.TagNumber(4)
  set truncated($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTruncated() => $_has(3);
  @$pb.TagNumber(4)
  void clearTruncated() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sampledAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set sampledAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSampledAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearSampledAtMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get coverage => $_getSZ(5);
  @$pb.TagNumber(6)
  set coverage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCoverage() => $_has(5);
  @$pb.TagNumber(6)
  void clearCoverage() => $_clearField(6);
}

class PriorityAP extends $pb.GeneratedMessage {
  factory PriorityAP({
    $core.String? bssid,
    $core.String? ssid,
    $core.String? channel,
    $core.double? rssiDbm,
    $core.String? security,
    $fixnum.Int64? frequencyKhz,
    $fixnum.Int64? firstSeenMs,
    $fixnum.Int64? lastSeenMs,
  }) {
    final result = PriorityAP._();
    if (bssid != null) result.bssid = bssid;
    if (ssid != null) result.ssid = ssid;
    if (channel != null) result.channel = channel;
    if (rssiDbm != null) result.rssiDbm = rssiDbm;
    if (security != null) result.security = security;
    if (frequencyKhz != null) result.frequencyKhz = frequencyKhz;
    if (firstSeenMs != null) result.firstSeenMs = firstSeenMs;
    if (lastSeenMs != null) result.lastSeenMs = lastSeenMs;
    return result;
  }

  PriorityAP._();

  factory PriorityAP.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PriorityAP()..mergeFromBuffer(data, registry);
  factory PriorityAP.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PriorityAP()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PriorityAP',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: PriorityAP.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'bssid')
    ..aOS(2, _omitFieldNames ? '' : 'ssid')
    ..aOS(3, _omitFieldNames ? '' : 'channel')
    ..aD(4, _omitFieldNames ? '' : 'rssiDbm', fieldType: $pb.PbFieldType.OF)
    ..aOS(5, _omitFieldNames ? '' : 'security')
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'frequencyKhz', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(7, _omitFieldNames ? '' : 'firstSeenMs')
    ..aInt64(8, _omitFieldNames ? '' : 'lastSeenMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PriorityAP clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PriorityAP copyWith(void Function(PriorityAP) updates) =>
      super.copyWith((message) => updates(message as PriorityAP)) as PriorityAP;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PriorityAP() / PriorityAP.new instead')
  static PriorityAP create() => PriorityAP._();
  static $pb.GeneratedMessage $_createMessage() => PriorityAP._();
  @$core.override
  PriorityAP createEmptyInstance() => PriorityAP._();
  @$core.pragma('dart2js:noInline')
  static PriorityAP getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PriorityAP>(PriorityAP.$_createMessage);
  static PriorityAP? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get bssid => $_getSZ(0);
  @$pb.TagNumber(1)
  set bssid($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBssid() => $_has(0);
  @$pb.TagNumber(1)
  void clearBssid() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get ssid => $_getSZ(1);
  @$pb.TagNumber(2)
  set ssid($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSsid() => $_has(1);
  @$pb.TagNumber(2)
  void clearSsid() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get channel => $_getSZ(2);
  @$pb.TagNumber(3)
  set channel($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChannel() => $_has(2);
  @$pb.TagNumber(3)
  void clearChannel() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get rssiDbm => $_getN(3);
  @$pb.TagNumber(4)
  set rssiDbm($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRssiDbm() => $_has(3);
  @$pb.TagNumber(4)
  void clearRssiDbm() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get security => $_getSZ(4);
  @$pb.TagNumber(5)
  set security($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSecurity() => $_has(4);
  @$pb.TagNumber(5)
  void clearSecurity() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get frequencyKhz => $_getI64(5);
  @$pb.TagNumber(6)
  set frequencyKhz($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasFrequencyKhz() => $_has(5);
  @$pb.TagNumber(6)
  void clearFrequencyKhz() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get firstSeenMs => $_getI64(6);
  @$pb.TagNumber(7)
  set firstSeenMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasFirstSeenMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearFirstSeenMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get lastSeenMs => $_getI64(7);
  @$pb.TagNumber(8)
  set lastSeenMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLastSeenMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearLastSeenMs() => $_clearField(8);
}

class MonitoringEvent extends $pb.GeneratedMessage {
  factory MonitoringEvent({
    $core.String? bootId,
    $core.String? eventId,
    $fixnum.Int64? sequence,
    $fixnum.Int64? timestampMs,
    $core.String? eventType,
    EventPriority? priority,
    $core.String? source,
    $core.String? bssid,
    $core.String? description,
    $core.String? evidenceId,
    $core.int? occurrences,
    EventCategory? eventCategory,
    RiskClass? riskClass,
    Confidence? confidence,
    $core.String? sourceScope,
    $core.String? summary,
    $fixnum.Int64? observedAtMs,
  }) {
    final result = MonitoringEvent._();
    if (bootId != null) result.bootId = bootId;
    if (eventId != null) result.eventId = eventId;
    if (sequence != null) result.sequence = sequence;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (eventType != null) result.eventType = eventType;
    if (priority != null) result.priority = priority;
    if (source != null) result.source = source;
    if (bssid != null) result.bssid = bssid;
    if (description != null) result.description = description;
    if (evidenceId != null) result.evidenceId = evidenceId;
    if (occurrences != null) result.occurrences = occurrences;
    if (eventCategory != null) result.eventCategory = eventCategory;
    if (riskClass != null) result.riskClass = riskClass;
    if (confidence != null) result.confidence = confidence;
    if (sourceScope != null) result.sourceScope = sourceScope;
    if (summary != null) result.summary = summary;
    if (observedAtMs != null) result.observedAtMs = observedAtMs;
    return result;
  }

  MonitoringEvent._();

  factory MonitoringEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MonitoringEvent()..mergeFromBuffer(data, registry);
  factory MonitoringEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MonitoringEvent()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MonitoringEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: MonitoringEvent.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'bootId')
    ..aOS(2, _omitFieldNames ? '' : 'eventId')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(4, _omitFieldNames ? '' : 'timestampMs')
    ..aOS(5, _omitFieldNames ? '' : 'eventType')
    ..aE<EventPriority>(6, _omitFieldNames ? '' : 'priority',
        enumValues: EventPriority.values)
    ..aOS(7, _omitFieldNames ? '' : 'source')
    ..aOS(8, _omitFieldNames ? '' : 'bssid')
    ..aOS(9, _omitFieldNames ? '' : 'description')
    ..aOS(10, _omitFieldNames ? '' : 'evidenceId')
    ..aI(11, _omitFieldNames ? '' : 'occurrences',
        fieldType: $pb.PbFieldType.OU3)
    ..aE<EventCategory>(12, _omitFieldNames ? '' : 'eventCategory',
        enumValues: EventCategory.values)
    ..aE<RiskClass>(13, _omitFieldNames ? '' : 'riskClass',
        enumValues: RiskClass.values)
    ..aE<Confidence>(14, _omitFieldNames ? '' : 'confidence',
        enumValues: Confidence.values)
    ..aOS(15, _omitFieldNames ? '' : 'sourceScope')
    ..aOS(16, _omitFieldNames ? '' : 'summary')
    ..aInt64(17, _omitFieldNames ? '' : 'observedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MonitoringEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MonitoringEvent copyWith(void Function(MonitoringEvent) updates) =>
      super.copyWith((message) => updates(message as MonitoringEvent))
          as MonitoringEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MonitoringEvent() / MonitoringEvent.new instead')
  static MonitoringEvent create() => MonitoringEvent._();
  static $pb.GeneratedMessage $_createMessage() => MonitoringEvent._();
  @$core.override
  MonitoringEvent createEmptyInstance() => MonitoringEvent._();
  @$core.pragma('dart2js:noInline')
  static MonitoringEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MonitoringEvent>(
          MonitoringEvent.$_createMessage);
  static MonitoringEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get bootId => $_getSZ(0);
  @$pb.TagNumber(1)
  set bootId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBootId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBootId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get eventId => $_getSZ(1);
  @$pb.TagNumber(2)
  set eventId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventId() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sequence => $_getI64(2);
  @$pb.TagNumber(3)
  set sequence($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSequence() => $_has(2);
  @$pb.TagNumber(3)
  void clearSequence() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampMs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimestampMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get eventType => $_getSZ(4);
  @$pb.TagNumber(5)
  set eventType($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEventType() => $_has(4);
  @$pb.TagNumber(5)
  void clearEventType() => $_clearField(5);

  @$pb.TagNumber(6)
  EventPriority get priority => $_getN(5);
  @$pb.TagNumber(6)
  set priority(EventPriority value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPriority() => $_has(5);
  @$pb.TagNumber(6)
  void clearPriority() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get source => $_getSZ(6);
  @$pb.TagNumber(7)
  set source($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSource() => $_has(6);
  @$pb.TagNumber(7)
  void clearSource() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get bssid => $_getSZ(7);
  @$pb.TagNumber(8)
  set bssid($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBssid() => $_has(7);
  @$pb.TagNumber(8)
  void clearBssid() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get description => $_getSZ(8);
  @$pb.TagNumber(9)
  set description($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasDescription() => $_has(8);
  @$pb.TagNumber(9)
  void clearDescription() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get evidenceId => $_getSZ(9);
  @$pb.TagNumber(10)
  set evidenceId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasEvidenceId() => $_has(9);
  @$pb.TagNumber(10)
  void clearEvidenceId() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get occurrences => $_getIZ(10);
  @$pb.TagNumber(11)
  set occurrences($core.int value) => $_setUnsignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasOccurrences() => $_has(10);
  @$pb.TagNumber(11)
  void clearOccurrences() => $_clearField(11);

  @$pb.TagNumber(12)
  EventCategory get eventCategory => $_getN(11);
  @$pb.TagNumber(12)
  set eventCategory(EventCategory value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasEventCategory() => $_has(11);
  @$pb.TagNumber(12)
  void clearEventCategory() => $_clearField(12);

  @$pb.TagNumber(13)
  RiskClass get riskClass => $_getN(12);
  @$pb.TagNumber(13)
  set riskClass(RiskClass value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasRiskClass() => $_has(12);
  @$pb.TagNumber(13)
  void clearRiskClass() => $_clearField(13);

  @$pb.TagNumber(14)
  Confidence get confidence => $_getN(13);
  @$pb.TagNumber(14)
  set confidence(Confidence value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasConfidence() => $_has(13);
  @$pb.TagNumber(14)
  void clearConfidence() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get sourceScope => $_getSZ(14);
  @$pb.TagNumber(15)
  set sourceScope($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasSourceScope() => $_has(14);
  @$pb.TagNumber(15)
  void clearSourceScope() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get summary => $_getSZ(15);
  @$pb.TagNumber(16)
  set summary($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasSummary() => $_has(15);
  @$pb.TagNumber(16)
  void clearSummary() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get observedAtMs => $_getI64(16);
  @$pb.TagNumber(17)
  set observedAtMs($fixnum.Int64 value) => $_setInt64(16, value);
  @$pb.TagNumber(17)
  $core.bool hasObservedAtMs() => $_has(16);
  @$pb.TagNumber(17)
  void clearObservedAtMs() => $_clearField(17);
}

class DeliveryMetrics extends $pb.GeneratedMessage {
  factory DeliveryMetrics({
    $fixnum.Int64? droppedEvents,
    $fixnum.Int64? mergedEvents,
    $core.int? pendingEvents,
  }) {
    final result = DeliveryMetrics._();
    if (droppedEvents != null) result.droppedEvents = droppedEvents;
    if (mergedEvents != null) result.mergedEvents = mergedEvents;
    if (pendingEvents != null) result.pendingEvents = pendingEvents;
    return result;
  }

  DeliveryMetrics._();

  factory DeliveryMetrics.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeliveryMetrics()..mergeFromBuffer(data, registry);
  factory DeliveryMetrics.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeliveryMetrics()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeliveryMetrics',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: DeliveryMetrics.$_createMessage)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'droppedEvents', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'mergedEvents', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aI(3, _omitFieldNames ? '' : 'pendingEvents',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeliveryMetrics clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeliveryMetrics copyWith(void Function(DeliveryMetrics) updates) =>
      super.copyWith((message) => updates(message as DeliveryMetrics))
          as DeliveryMetrics;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeliveryMetrics() / DeliveryMetrics.new instead')
  static DeliveryMetrics create() => DeliveryMetrics._();
  static $pb.GeneratedMessage $_createMessage() => DeliveryMetrics._();
  @$core.override
  DeliveryMetrics createEmptyInstance() => DeliveryMetrics._();
  @$core.pragma('dart2js:noInline')
  static DeliveryMetrics getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeliveryMetrics>(
          DeliveryMetrics.$_createMessage);
  static DeliveryMetrics? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get droppedEvents => $_getI64(0);
  @$pb.TagNumber(1)
  set droppedEvents($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDroppedEvents() => $_has(0);
  @$pb.TagNumber(1)
  void clearDroppedEvents() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get mergedEvents => $_getI64(1);
  @$pb.TagNumber(2)
  set mergedEvents($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMergedEvents() => $_has(1);
  @$pb.TagNumber(2)
  void clearMergedEvents() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get pendingEvents => $_getIZ(2);
  @$pb.TagNumber(3)
  set pendingEvents($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPendingEvents() => $_has(2);
  @$pb.TagNumber(3)
  void clearPendingEvents() => $_clearField(3);
}

class HighRiskEnvelope extends $pb.GeneratedMessage {
  factory HighRiskEnvelope({
    $core.String? durableId,
    MonitoringEvent? event,
    $core.int? ttlSeconds,
    $fixnum.Int64? enqueuedWallMs,
  }) {
    final result = HighRiskEnvelope._();
    if (durableId != null) result.durableId = durableId;
    if (event != null) result.event = event;
    if (ttlSeconds != null) result.ttlSeconds = ttlSeconds;
    if (enqueuedWallMs != null) result.enqueuedWallMs = enqueuedWallMs;
    return result;
  }

  HighRiskEnvelope._();

  factory HighRiskEnvelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HighRiskEnvelope()..mergeFromBuffer(data, registry);
  factory HighRiskEnvelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HighRiskEnvelope()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HighRiskEnvelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: HighRiskEnvelope.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'durableId')
    ..aOM<MonitoringEvent>(2, _omitFieldNames ? '' : 'event',
        subBuilder: MonitoringEvent.$_createMessage)
    ..aI(3, _omitFieldNames ? '' : 'ttlSeconds', fieldType: $pb.PbFieldType.OU3)
    ..aInt64(4, _omitFieldNames ? '' : 'enqueuedWallMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HighRiskEnvelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HighRiskEnvelope copyWith(void Function(HighRiskEnvelope) updates) =>
      super.copyWith((message) => updates(message as HighRiskEnvelope))
          as HighRiskEnvelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use HighRiskEnvelope() / HighRiskEnvelope.new instead')
  static HighRiskEnvelope create() => HighRiskEnvelope._();
  static $pb.GeneratedMessage $_createMessage() => HighRiskEnvelope._();
  @$core.override
  HighRiskEnvelope createEmptyInstance() => HighRiskEnvelope._();
  @$core.pragma('dart2js:noInline')
  static HighRiskEnvelope getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<HighRiskEnvelope>(
          HighRiskEnvelope.$_createMessage);
  static HighRiskEnvelope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get durableId => $_getSZ(0);
  @$pb.TagNumber(1)
  set durableId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDurableId() => $_has(0);
  @$pb.TagNumber(1)
  void clearDurableId() => $_clearField(1);

  @$pb.TagNumber(2)
  MonitoringEvent get event => $_getN(1);
  @$pb.TagNumber(2)
  set event(MonitoringEvent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasEvent() => $_has(1);
  @$pb.TagNumber(2)
  void clearEvent() => $_clearField(2);
  @$pb.TagNumber(2)
  MonitoringEvent ensureEvent() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.int get ttlSeconds => $_getIZ(2);
  @$pb.TagNumber(3)
  set ttlSeconds($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTtlSeconds() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtlSeconds() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get enqueuedWallMs => $_getI64(3);
  @$pb.TagNumber(4)
  set enqueuedWallMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEnqueuedWallMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearEnqueuedWallMs() => $_clearField(4);
}

class AckHighRiskRequest extends $pb.GeneratedMessage {
  factory AckHighRiskRequest({
    $core.String? phoneId,
    $core.String? durableId,
  }) {
    final result = AckHighRiskRequest._();
    if (phoneId != null) result.phoneId = phoneId;
    if (durableId != null) result.durableId = durableId;
    return result;
  }

  AckHighRiskRequest._();

  factory AckHighRiskRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AckHighRiskRequest()..mergeFromBuffer(data, registry);
  factory AckHighRiskRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AckHighRiskRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AckHighRiskRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: AckHighRiskRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'phoneId')
    ..aOS(2, _omitFieldNames ? '' : 'durableId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckHighRiskRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckHighRiskRequest copyWith(void Function(AckHighRiskRequest) updates) =>
      super.copyWith((message) => updates(message as AckHighRiskRequest))
          as AckHighRiskRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AckHighRiskRequest() / AckHighRiskRequest.new instead')
  static AckHighRiskRequest create() => AckHighRiskRequest._();
  static $pb.GeneratedMessage $_createMessage() => AckHighRiskRequest._();
  @$core.override
  AckHighRiskRequest createEmptyInstance() => AckHighRiskRequest._();
  @$core.pragma('dart2js:noInline')
  static AckHighRiskRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AckHighRiskRequest>(
          AckHighRiskRequest.$_createMessage);
  static AckHighRiskRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get phoneId => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get durableId => $_getSZ(1);
  @$pb.TagNumber(2)
  set durableId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDurableId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDurableId() => $_clearField(2);
}

class AckHighRiskResponse extends $pb.GeneratedMessage {
  factory AckHighRiskResponse({
    $core.String? result,
  }) {
    final result$ = AckHighRiskResponse._();
    if (result != null) result$.result = result;
    return result$;
  }

  AckHighRiskResponse._();

  factory AckHighRiskResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AckHighRiskResponse()..mergeFromBuffer(data, registry);
  factory AckHighRiskResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AckHighRiskResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AckHighRiskResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: AckHighRiskResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'result')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckHighRiskResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AckHighRiskResponse copyWith(void Function(AckHighRiskResponse) updates) =>
      super.copyWith((message) => updates(message as AckHighRiskResponse))
          as AckHighRiskResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use AckHighRiskResponse() / AckHighRiskResponse.new instead')
  static AckHighRiskResponse create() => AckHighRiskResponse._();
  static $pb.GeneratedMessage $_createMessage() => AckHighRiskResponse._();
  @$core.override
  AckHighRiskResponse createEmptyInstance() => AckHighRiskResponse._();
  @$core.pragma('dart2js:noInline')
  static AckHighRiskResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AckHighRiskResponse>(
          AckHighRiskResponse.$_createMessage);
  static AckHighRiskResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get result => $_getSZ(0);
  @$pb.TagNumber(1)
  set result($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResult() => $_has(0);
  @$pb.TagNumber(1)
  void clearResult() => $_clearField(1);
}

class CapturePolicyStatus extends $pb.GeneratedMessage {
  factory CapturePolicyStatus({
    $core.String? requested,
    $core.String? actual,
    $core.String? phase,
    $core.String? reason,
    $core.bool? pressureForced,
  }) {
    final result = CapturePolicyStatus._();
    if (requested != null) result.requested = requested;
    if (actual != null) result.actual = actual;
    if (phase != null) result.phase = phase;
    if (reason != null) result.reason = reason;
    if (pressureForced != null) result.pressureForced = pressureForced;
    return result;
  }

  CapturePolicyStatus._();

  factory CapturePolicyStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CapturePolicyStatus()..mergeFromBuffer(data, registry);
  factory CapturePolicyStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CapturePolicyStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CapturePolicyStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: CapturePolicyStatus.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'requested')
    ..aOS(2, _omitFieldNames ? '' : 'actual')
    ..aOS(3, _omitFieldNames ? '' : 'phase')
    ..aOS(4, _omitFieldNames ? '' : 'reason')
    ..aOB(5, _omitFieldNames ? '' : 'pressureForced')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CapturePolicyStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CapturePolicyStatus copyWith(void Function(CapturePolicyStatus) updates) =>
      super.copyWith((message) => updates(message as CapturePolicyStatus))
          as CapturePolicyStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use CapturePolicyStatus() / CapturePolicyStatus.new instead')
  static CapturePolicyStatus create() => CapturePolicyStatus._();
  static $pb.GeneratedMessage $_createMessage() => CapturePolicyStatus._();
  @$core.override
  CapturePolicyStatus createEmptyInstance() => CapturePolicyStatus._();
  @$core.pragma('dart2js:noInline')
  static CapturePolicyStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CapturePolicyStatus>(
          CapturePolicyStatus.$_createMessage);
  static CapturePolicyStatus? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requested => $_getSZ(0);
  @$pb.TagNumber(1)
  set requested($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequested() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequested() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get actual => $_getSZ(1);
  @$pb.TagNumber(2)
  set actual($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasActual() => $_has(1);
  @$pb.TagNumber(2)
  void clearActual() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get phase => $_getSZ(2);
  @$pb.TagNumber(3)
  set phase($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPhase() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhase() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get reason => $_getSZ(3);
  @$pb.TagNumber(4)
  set reason($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasReason() => $_has(3);
  @$pb.TagNumber(4)
  void clearReason() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get pressureForced => $_getBF(4);
  @$pb.TagNumber(5)
  set pressureForced($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasPressureForced() => $_has(4);
  @$pb.TagNumber(5)
  void clearPressureForced() => $_clearField(5);
}

class ObservationSession extends $pb.GeneratedMessage {
  factory ObservationSession({
    $core.String? sessionId,
    $core.bool? active,
    $fixnum.Int64? continuousActiveMs,
    $core.String? resetReason,
  }) {
    final result = ObservationSession._();
    if (sessionId != null) result.sessionId = sessionId;
    if (active != null) result.active = active;
    if (continuousActiveMs != null)
      result.continuousActiveMs = continuousActiveMs;
    if (resetReason != null) result.resetReason = resetReason;
    return result;
  }

  ObservationSession._();

  factory ObservationSession.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservationSession()..mergeFromBuffer(data, registry);
  factory ObservationSession.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservationSession()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ObservationSession',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: ObservationSession.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sessionId')
    ..aOB(2, _omitFieldNames ? '' : 'active')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'continuousActiveMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'resetReason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservationSession clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservationSession copyWith(void Function(ObservationSession) updates) =>
      super.copyWith((message) => updates(message as ObservationSession))
          as ObservationSession;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ObservationSession() / ObservationSession.new instead')
  static ObservationSession create() => ObservationSession._();
  static $pb.GeneratedMessage $_createMessage() => ObservationSession._();
  @$core.override
  ObservationSession createEmptyInstance() => ObservationSession._();
  @$core.pragma('dart2js:noInline')
  static ObservationSession getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ObservationSession>(
          ObservationSession.$_createMessage);
  static ObservationSession? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get active => $_getBF(1);
  @$pb.TagNumber(2)
  set active($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasActive() => $_has(1);
  @$pb.TagNumber(2)
  void clearActive() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get continuousActiveMs => $_getI64(2);
  @$pb.TagNumber(3)
  set continuousActiveMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContinuousActiveMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearContinuousActiveMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get resetReason => $_getSZ(3);
  @$pb.TagNumber(4)
  set resetReason($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasResetReason() => $_has(3);
  @$pb.TagNumber(4)
  void clearResetReason() => $_clearField(4);
}

class HighRiskDeliveryStatus extends $pb.GeneratedMessage {
  factory HighRiskDeliveryStatus({
    $core.int? pendingCount,
    $fixnum.Int64? pendingBytes,
    $fixnum.Int64? ackedCount,
    $fixnum.Int64? expiredCount,
    $fixnum.Int64? overflowEvictedCount,
    $fixnum.Int64? storageErrorCount,
    $fixnum.Int64? overflowRejectedCount,
    $fixnum.Int64? oversizeRejectedCount,
    $fixnum.Int64? previousBootDiscardedCount,
    $core.bool? storageAvailable,
  }) {
    final result = HighRiskDeliveryStatus._();
    if (pendingCount != null) result.pendingCount = pendingCount;
    if (pendingBytes != null) result.pendingBytes = pendingBytes;
    if (ackedCount != null) result.ackedCount = ackedCount;
    if (expiredCount != null) result.expiredCount = expiredCount;
    if (overflowEvictedCount != null)
      result.overflowEvictedCount = overflowEvictedCount;
    if (storageErrorCount != null) result.storageErrorCount = storageErrorCount;
    if (overflowRejectedCount != null)
      result.overflowRejectedCount = overflowRejectedCount;
    if (oversizeRejectedCount != null)
      result.oversizeRejectedCount = oversizeRejectedCount;
    if (previousBootDiscardedCount != null)
      result.previousBootDiscardedCount = previousBootDiscardedCount;
    if (storageAvailable != null) result.storageAvailable = storageAvailable;
    return result;
  }

  HighRiskDeliveryStatus._();

  factory HighRiskDeliveryStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HighRiskDeliveryStatus()..mergeFromBuffer(data, registry);
  factory HighRiskDeliveryStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      HighRiskDeliveryStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HighRiskDeliveryStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: HighRiskDeliveryStatus.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'pendingCount',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'pendingBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'ackedCount', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'expiredCount', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'overflowEvictedCount', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'storageErrorCount', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        7, _omitFieldNames ? '' : 'overflowRejectedCount', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'oversizeRejectedCount', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(9, _omitFieldNames ? '' : 'previousBootDiscardedCount',
        $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(10, _omitFieldNames ? '' : 'storageAvailable')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HighRiskDeliveryStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HighRiskDeliveryStatus copyWith(
          void Function(HighRiskDeliveryStatus) updates) =>
      super.copyWith((message) => updates(message as HighRiskDeliveryStatus))
          as HighRiskDeliveryStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use HighRiskDeliveryStatus() / HighRiskDeliveryStatus.new instead')
  static HighRiskDeliveryStatus create() => HighRiskDeliveryStatus._();
  static $pb.GeneratedMessage $_createMessage() => HighRiskDeliveryStatus._();
  @$core.override
  HighRiskDeliveryStatus createEmptyInstance() => HighRiskDeliveryStatus._();
  @$core.pragma('dart2js:noInline')
  static HighRiskDeliveryStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HighRiskDeliveryStatus>(
          HighRiskDeliveryStatus.$_createMessage);
  static HighRiskDeliveryStatus? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get pendingCount => $_getIZ(0);
  @$pb.TagNumber(1)
  set pendingCount($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPendingCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearPendingCount() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get pendingBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set pendingBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPendingBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearPendingBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get ackedCount => $_getI64(2);
  @$pb.TagNumber(3)
  set ackedCount($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAckedCount() => $_has(2);
  @$pb.TagNumber(3)
  void clearAckedCount() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get expiredCount => $_getI64(3);
  @$pb.TagNumber(4)
  set expiredCount($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpiredCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpiredCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get overflowEvictedCount => $_getI64(4);
  @$pb.TagNumber(5)
  set overflowEvictedCount($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOverflowEvictedCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearOverflowEvictedCount() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get storageErrorCount => $_getI64(5);
  @$pb.TagNumber(6)
  set storageErrorCount($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStorageErrorCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearStorageErrorCount() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get overflowRejectedCount => $_getI64(6);
  @$pb.TagNumber(7)
  set overflowRejectedCount($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasOverflowRejectedCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearOverflowRejectedCount() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get oversizeRejectedCount => $_getI64(7);
  @$pb.TagNumber(8)
  set oversizeRejectedCount($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasOversizeRejectedCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearOversizeRejectedCount() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get previousBootDiscardedCount => $_getI64(8);
  @$pb.TagNumber(9)
  set previousBootDiscardedCount($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasPreviousBootDiscardedCount() => $_has(8);
  @$pb.TagNumber(9)
  void clearPreviousBootDiscardedCount() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get storageAvailable => $_getBF(9);
  @$pb.TagNumber(10)
  set storageAvailable($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasStorageAvailable() => $_has(9);
  @$pb.TagNumber(10)
  void clearStorageAvailable() => $_clearField(10);
}

class ResourcePressureStatus extends $pb.GeneratedMessage {
  factory ResourcePressureStatus({
    ResourceLevel? level,
    $core.String? reason,
  }) {
    final result = ResourcePressureStatus._();
    if (level != null) result.level = level;
    if (reason != null) result.reason = reason;
    return result;
  }

  ResourcePressureStatus._();

  factory ResourcePressureStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResourcePressureStatus()..mergeFromBuffer(data, registry);
  factory ResourcePressureStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResourcePressureStatus()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResourcePressureStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: ResourcePressureStatus.$_createMessage)
    ..aE<ResourceLevel>(1, _omitFieldNames ? '' : 'level',
        enumValues: ResourceLevel.values)
    ..aOS(2, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResourcePressureStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResourcePressureStatus copyWith(
          void Function(ResourcePressureStatus) updates) =>
      super.copyWith((message) => updates(message as ResourcePressureStatus))
          as ResourcePressureStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ResourcePressureStatus() / ResourcePressureStatus.new instead')
  static ResourcePressureStatus create() => ResourcePressureStatus._();
  static $pb.GeneratedMessage $_createMessage() => ResourcePressureStatus._();
  @$core.override
  ResourcePressureStatus createEmptyInstance() => ResourcePressureStatus._();
  @$core.pragma('dart2js:noInline')
  static ResourcePressureStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResourcePressureStatus>(
          ResourcePressureStatus.$_createMessage);
  static ResourcePressureStatus? _defaultInstance;

  @$pb.TagNumber(1)
  ResourceLevel get level => $_getN(0);
  @$pb.TagNumber(1)
  set level(ResourceLevel value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasLevel() => $_has(0);
  @$pb.TagNumber(1)
  void clearLevel() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get reason => $_getSZ(1);
  @$pb.TagNumber(2)
  set reason($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReason() => $_has(1);
  @$pb.TagNumber(2)
  void clearReason() => $_clearField(2);
}

class ComponentHealth extends $pb.GeneratedMessage {
  factory ComponentHealth({
    ComponentId? componentId,
    ComponentState? state,
    $core.String? reason,
    $fixnum.Int64? lastOkMs,
    $fixnum.Int64? sampledAtMs,
    $core.String? recoveryPhase,
  }) {
    final result = ComponentHealth._();
    if (componentId != null) result.componentId = componentId;
    if (state != null) result.state = state;
    if (reason != null) result.reason = reason;
    if (lastOkMs != null) result.lastOkMs = lastOkMs;
    if (sampledAtMs != null) result.sampledAtMs = sampledAtMs;
    if (recoveryPhase != null) result.recoveryPhase = recoveryPhase;
    return result;
  }

  ComponentHealth._();

  factory ComponentHealth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ComponentHealth()..mergeFromBuffer(data, registry);
  factory ComponentHealth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ComponentHealth()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComponentHealth',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: ComponentHealth.$_createMessage)
    ..aE<ComponentId>(1, _omitFieldNames ? '' : 'componentId',
        enumValues: ComponentId.values)
    ..aE<ComponentState>(2, _omitFieldNames ? '' : 'state',
        enumValues: ComponentState.values)
    ..aOS(3, _omitFieldNames ? '' : 'reason')
    ..aInt64(4, _omitFieldNames ? '' : 'lastOkMs')
    ..aInt64(5, _omitFieldNames ? '' : 'sampledAtMs')
    ..aOS(6, _omitFieldNames ? '' : 'recoveryPhase')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentHealth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentHealth copyWith(void Function(ComponentHealth) updates) =>
      super.copyWith((message) => updates(message as ComponentHealth))
          as ComponentHealth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ComponentHealth() / ComponentHealth.new instead')
  static ComponentHealth create() => ComponentHealth._();
  static $pb.GeneratedMessage $_createMessage() => ComponentHealth._();
  @$core.override
  ComponentHealth createEmptyInstance() => ComponentHealth._();
  @$core.pragma('dart2js:noInline')
  static ComponentHealth getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ComponentHealth>(
          ComponentHealth.$_createMessage);
  static ComponentHealth? _defaultInstance;

  @$pb.TagNumber(1)
  ComponentId get componentId => $_getN(0);
  @$pb.TagNumber(1)
  set componentId(ComponentId value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasComponentId() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponentId() => $_clearField(1);

  @$pb.TagNumber(2)
  ComponentState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(ComponentState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get reason => $_getSZ(2);
  @$pb.TagNumber(3)
  set reason($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReason() => $_has(2);
  @$pb.TagNumber(3)
  void clearReason() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get lastOkMs => $_getI64(3);
  @$pb.TagNumber(4)
  set lastOkMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLastOkMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastOkMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sampledAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set sampledAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSampledAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearSampledAtMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get recoveryPhase => $_getSZ(5);
  @$pb.TagNumber(6)
  set recoveryPhase($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRecoveryPhase() => $_has(5);
  @$pb.TagNumber(6)
  void clearRecoveryPhase() => $_clearField(6);
}

class DeviceHealth extends $pb.GeneratedMessage {
  factory DeviceHealth({
    $core.Iterable<ComponentHealth>? components,
  }) {
    final result = DeviceHealth._();
    if (components != null) result.components.addAll(components);
    return result;
  }

  DeviceHealth._();

  factory DeviceHealth.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceHealth()..mergeFromBuffer(data, registry);
  factory DeviceHealth.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeviceHealth()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceHealth',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: DeviceHealth.$_createMessage)
    ..pPM<ComponentHealth>(1, _omitFieldNames ? '' : 'components',
        subBuilder: ComponentHealth.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceHealth clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceHealth copyWith(void Function(DeviceHealth) updates) =>
      super.copyWith((message) => updates(message as DeviceHealth))
          as DeviceHealth;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeviceHealth() / DeviceHealth.new instead')
  static DeviceHealth create() => DeviceHealth._();
  static $pb.GeneratedMessage $_createMessage() => DeviceHealth._();
  @$core.override
  DeviceHealth createEmptyInstance() => DeviceHealth._();
  @$core.pragma('dart2js:noInline')
  static DeviceHealth getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeviceHealth>(
          DeviceHealth.$_createMessage);
  static DeviceHealth? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ComponentHealth> get components => $_getList(0);
}

class ObservedDevice extends $pb.GeneratedMessage {
  factory ObservedDevice({
    $core.String? deviceKey,
    $core.String? mac,
    ObservedDeviceKind? kind,
    $core.String? ssid,
    $core.String? bssid,
    $core.String? channel,
    $core.double? rssiDbm,
    $fixnum.Int64? firstSeenMs,
    $fixnum.Int64? lastSeenMs,
    AssociationState? associationState,
    $core.String? relatedApBssid,
    $core.String? sourceScope,
    $core.String? security,
  }) {
    final result = ObservedDevice._();
    if (deviceKey != null) result.deviceKey = deviceKey;
    if (mac != null) result.mac = mac;
    if (kind != null) result.kind = kind;
    if (ssid != null) result.ssid = ssid;
    if (bssid != null) result.bssid = bssid;
    if (channel != null) result.channel = channel;
    if (rssiDbm != null) result.rssiDbm = rssiDbm;
    if (firstSeenMs != null) result.firstSeenMs = firstSeenMs;
    if (lastSeenMs != null) result.lastSeenMs = lastSeenMs;
    if (associationState != null) result.associationState = associationState;
    if (relatedApBssid != null) result.relatedApBssid = relatedApBssid;
    if (sourceScope != null) result.sourceScope = sourceScope;
    if (security != null) result.security = security;
    return result;
  }

  ObservedDevice._();

  factory ObservedDevice.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservedDevice()..mergeFromBuffer(data, registry);
  factory ObservedDevice.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservedDevice()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ObservedDevice',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: ObservedDevice.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'deviceKey')
    ..aOS(2, _omitFieldNames ? '' : 'mac')
    ..aE<ObservedDeviceKind>(3, _omitFieldNames ? '' : 'kind',
        enumValues: ObservedDeviceKind.values)
    ..aOS(4, _omitFieldNames ? '' : 'ssid')
    ..aOS(5, _omitFieldNames ? '' : 'bssid')
    ..aOS(6, _omitFieldNames ? '' : 'channel')
    ..aD(7, _omitFieldNames ? '' : 'rssiDbm', fieldType: $pb.PbFieldType.OF)
    ..aInt64(8, _omitFieldNames ? '' : 'firstSeenMs')
    ..aInt64(9, _omitFieldNames ? '' : 'lastSeenMs')
    ..aE<AssociationState>(10, _omitFieldNames ? '' : 'associationState',
        enumValues: AssociationState.values)
    ..aOS(11, _omitFieldNames ? '' : 'relatedApBssid')
    ..aOS(12, _omitFieldNames ? '' : 'sourceScope')
    ..aOS(13, _omitFieldNames ? '' : 'security')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservedDevice clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservedDevice copyWith(void Function(ObservedDevice) updates) =>
      super.copyWith((message) => updates(message as ObservedDevice))
          as ObservedDevice;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ObservedDevice() / ObservedDevice.new instead')
  static ObservedDevice create() => ObservedDevice._();
  static $pb.GeneratedMessage $_createMessage() => ObservedDevice._();
  @$core.override
  ObservedDevice createEmptyInstance() => ObservedDevice._();
  @$core.pragma('dart2js:noInline')
  static ObservedDevice getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ObservedDevice>(
          ObservedDevice.$_createMessage);
  static ObservedDevice? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get deviceKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set deviceKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDeviceKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearDeviceKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mac => $_getSZ(1);
  @$pb.TagNumber(2)
  set mac($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMac() => $_has(1);
  @$pb.TagNumber(2)
  void clearMac() => $_clearField(2);

  @$pb.TagNumber(3)
  ObservedDeviceKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(ObservedDeviceKind value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get ssid => $_getSZ(3);
  @$pb.TagNumber(4)
  set ssid($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSsid() => $_has(3);
  @$pb.TagNumber(4)
  void clearSsid() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get bssid => $_getSZ(4);
  @$pb.TagNumber(5)
  set bssid($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBssid() => $_has(4);
  @$pb.TagNumber(5)
  void clearBssid() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get channel => $_getSZ(5);
  @$pb.TagNumber(6)
  set channel($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasChannel() => $_has(5);
  @$pb.TagNumber(6)
  void clearChannel() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get rssiDbm => $_getN(6);
  @$pb.TagNumber(7)
  set rssiDbm($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRssiDbm() => $_has(6);
  @$pb.TagNumber(7)
  void clearRssiDbm() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get firstSeenMs => $_getI64(7);
  @$pb.TagNumber(8)
  set firstSeenMs($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasFirstSeenMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearFirstSeenMs() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get lastSeenMs => $_getI64(8);
  @$pb.TagNumber(9)
  set lastSeenMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLastSeenMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearLastSeenMs() => $_clearField(9);

  @$pb.TagNumber(10)
  AssociationState get associationState => $_getN(9);
  @$pb.TagNumber(10)
  set associationState(AssociationState value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasAssociationState() => $_has(9);
  @$pb.TagNumber(10)
  void clearAssociationState() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get relatedApBssid => $_getSZ(10);
  @$pb.TagNumber(11)
  set relatedApBssid($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasRelatedApBssid() => $_has(10);
  @$pb.TagNumber(11)
  void clearRelatedApBssid() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get sourceScope => $_getSZ(11);
  @$pb.TagNumber(12)
  set sourceScope($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasSourceScope() => $_has(11);
  @$pb.TagNumber(12)
  void clearSourceScope() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get security => $_getSZ(12);
  @$pb.TagNumber(13)
  set security($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasSecurity() => $_has(12);
  @$pb.TagNumber(13)
  void clearSecurity() => $_clearField(13);
}

class ObservedDevicesRequest extends $pb.GeneratedMessage {
  factory ObservedDevicesRequest({
    $core.String? phoneId,
    $core.String? pageToken,
    $core.int? pageSize,
    $core.String? ssidFilter,
    $core.String? bssidFilter,
    ObservedDeviceKind? kind,
  }) {
    final result = ObservedDevicesRequest._();
    if (phoneId != null) result.phoneId = phoneId;
    if (pageToken != null) result.pageToken = pageToken;
    if (pageSize != null) result.pageSize = pageSize;
    if (ssidFilter != null) result.ssidFilter = ssidFilter;
    if (bssidFilter != null) result.bssidFilter = bssidFilter;
    if (kind != null) result.kind = kind;
    return result;
  }

  ObservedDevicesRequest._();

  factory ObservedDevicesRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservedDevicesRequest()..mergeFromBuffer(data, registry);
  factory ObservedDevicesRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservedDevicesRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ObservedDevicesRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: ObservedDevicesRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'phoneId')
    ..aOS(2, _omitFieldNames ? '' : 'pageToken')
    ..aI(3, _omitFieldNames ? '' : 'pageSize', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'ssidFilter')
    ..aOS(5, _omitFieldNames ? '' : 'bssidFilter')
    ..aE<ObservedDeviceKind>(6, _omitFieldNames ? '' : 'kind',
        enumValues: ObservedDeviceKind.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservedDevicesRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservedDevicesRequest copyWith(
          void Function(ObservedDevicesRequest) updates) =>
      super.copyWith((message) => updates(message as ObservedDevicesRequest))
          as ObservedDevicesRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ObservedDevicesRequest() / ObservedDevicesRequest.new instead')
  static ObservedDevicesRequest create() => ObservedDevicesRequest._();
  static $pb.GeneratedMessage $_createMessage() => ObservedDevicesRequest._();
  @$core.override
  ObservedDevicesRequest createEmptyInstance() => ObservedDevicesRequest._();
  @$core.pragma('dart2js:noInline')
  static ObservedDevicesRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ObservedDevicesRequest>(
          ObservedDevicesRequest.$_createMessage);
  static ObservedDevicesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get phoneId => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get pageToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set pageToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPageToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get pageSize => $_getIZ(2);
  @$pb.TagNumber(3)
  set pageSize($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPageSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearPageSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get ssidFilter => $_getSZ(3);
  @$pb.TagNumber(4)
  set ssidFilter($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSsidFilter() => $_has(3);
  @$pb.TagNumber(4)
  void clearSsidFilter() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get bssidFilter => $_getSZ(4);
  @$pb.TagNumber(5)
  set bssidFilter($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBssidFilter() => $_has(4);
  @$pb.TagNumber(5)
  void clearBssidFilter() => $_clearField(5);

  @$pb.TagNumber(6)
  ObservedDeviceKind get kind => $_getN(5);
  @$pb.TagNumber(6)
  set kind(ObservedDeviceKind value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasKind() => $_has(5);
  @$pb.TagNumber(6)
  void clearKind() => $_clearField(6);
}

class ObservedDevicesPage extends $pb.GeneratedMessage {
  factory ObservedDevicesPage({
    $core.Iterable<ObservedDevice>? devices,
    $core.String? nextPageToken,
    $fixnum.Int64? generation,
    $core.bool? truncated,
    $fixnum.Int64? sampledAtMs,
    $core.String? coverage,
    $core.int? totalCount,
  }) {
    final result = ObservedDevicesPage._();
    if (devices != null) result.devices.addAll(devices);
    if (nextPageToken != null) result.nextPageToken = nextPageToken;
    if (generation != null) result.generation = generation;
    if (truncated != null) result.truncated = truncated;
    if (sampledAtMs != null) result.sampledAtMs = sampledAtMs;
    if (coverage != null) result.coverage = coverage;
    if (totalCount != null) result.totalCount = totalCount;
    return result;
  }

  ObservedDevicesPage._();

  factory ObservedDevicesPage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservedDevicesPage()..mergeFromBuffer(data, registry);
  factory ObservedDevicesPage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ObservedDevicesPage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ObservedDevicesPage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: ObservedDevicesPage.$_createMessage)
    ..pPM<ObservedDevice>(1, _omitFieldNames ? '' : 'devices',
        subBuilder: ObservedDevice.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'nextPageToken')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'generation', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(4, _omitFieldNames ? '' : 'truncated')
    ..aInt64(5, _omitFieldNames ? '' : 'sampledAtMs')
    ..aOS(6, _omitFieldNames ? '' : 'coverage')
    ..aI(7, _omitFieldNames ? '' : 'totalCount', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservedDevicesPage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ObservedDevicesPage copyWith(void Function(ObservedDevicesPage) updates) =>
      super.copyWith((message) => updates(message as ObservedDevicesPage))
          as ObservedDevicesPage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ObservedDevicesPage() / ObservedDevicesPage.new instead')
  static ObservedDevicesPage create() => ObservedDevicesPage._();
  static $pb.GeneratedMessage $_createMessage() => ObservedDevicesPage._();
  @$core.override
  ObservedDevicesPage createEmptyInstance() => ObservedDevicesPage._();
  @$core.pragma('dart2js:noInline')
  static ObservedDevicesPage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ObservedDevicesPage>(
          ObservedDevicesPage.$_createMessage);
  static ObservedDevicesPage? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<ObservedDevice> get devices => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get nextPageToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set nextPageToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNextPageToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearNextPageToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get generation => $_getI64(2);
  @$pb.TagNumber(3)
  set generation($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get truncated => $_getBF(3);
  @$pb.TagNumber(4)
  set truncated($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTruncated() => $_has(3);
  @$pb.TagNumber(4)
  void clearTruncated() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get sampledAtMs => $_getI64(4);
  @$pb.TagNumber(5)
  set sampledAtMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSampledAtMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearSampledAtMs() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get coverage => $_getSZ(5);
  @$pb.TagNumber(6)
  set coverage($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCoverage() => $_has(5);
  @$pb.TagNumber(6)
  void clearCoverage() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get totalCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set totalCount($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTotalCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearTotalCount() => $_clearField(7);
}

class SetCaptureProfileRequest extends $pb.GeneratedMessage {
  factory SetCaptureProfileRequest({
    $core.String? phoneId,
    $core.String? requestId,
    CaptureProfile? targetProfile,
  }) {
    final result = SetCaptureProfileRequest._();
    if (phoneId != null) result.phoneId = phoneId;
    if (requestId != null) result.requestId = requestId;
    if (targetProfile != null) result.targetProfile = targetProfile;
    return result;
  }

  SetCaptureProfileRequest._();

  factory SetCaptureProfileRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCaptureProfileRequest()..mergeFromBuffer(data, registry);
  factory SetCaptureProfileRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCaptureProfileRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetCaptureProfileRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: SetCaptureProfileRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'phoneId')
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aE<CaptureProfile>(3, _omitFieldNames ? '' : 'targetProfile',
        enumValues: CaptureProfile.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCaptureProfileRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCaptureProfileRequest copyWith(
          void Function(SetCaptureProfileRequest) updates) =>
      super.copyWith((message) => updates(message as SetCaptureProfileRequest))
          as SetCaptureProfileRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetCaptureProfileRequest() / SetCaptureProfileRequest.new instead')
  static SetCaptureProfileRequest create() => SetCaptureProfileRequest._();
  static $pb.GeneratedMessage $_createMessage() => SetCaptureProfileRequest._();
  @$core.override
  SetCaptureProfileRequest createEmptyInstance() =>
      SetCaptureProfileRequest._();
  @$core.pragma('dart2js:noInline')
  static SetCaptureProfileRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetCaptureProfileRequest>(
          SetCaptureProfileRequest.$_createMessage);
  static SetCaptureProfileRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get phoneId => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  CaptureProfile get targetProfile => $_getN(2);
  @$pb.TagNumber(3)
  set targetProfile(CaptureProfile value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasTargetProfile() => $_has(2);
  @$pb.TagNumber(3)
  void clearTargetProfile() => $_clearField(3);
}

class RecoverComponentRequest extends $pb.GeneratedMessage {
  factory RecoverComponentRequest({
    $core.String? phoneId,
    $core.String? requestId,
    ComponentId? component,
    $core.bool? allowHotspotRestart,
  }) {
    final result = RecoverComponentRequest._();
    if (phoneId != null) result.phoneId = phoneId;
    if (requestId != null) result.requestId = requestId;
    if (component != null) result.component = component;
    if (allowHotspotRestart != null)
      result.allowHotspotRestart = allowHotspotRestart;
    return result;
  }

  RecoverComponentRequest._();

  factory RecoverComponentRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoverComponentRequest()..mergeFromBuffer(data, registry);
  factory RecoverComponentRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RecoverComponentRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RecoverComponentRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: RecoverComponentRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'phoneId')
    ..aOS(2, _omitFieldNames ? '' : 'requestId')
    ..aE<ComponentId>(3, _omitFieldNames ? '' : 'component',
        enumValues: ComponentId.values)
    ..aOB(4, _omitFieldNames ? '' : 'allowHotspotRestart')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoverComponentRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RecoverComponentRequest copyWith(
          void Function(RecoverComponentRequest) updates) =>
      super.copyWith((message) => updates(message as RecoverComponentRequest))
          as RecoverComponentRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use RecoverComponentRequest() / RecoverComponentRequest.new instead')
  static RecoverComponentRequest create() => RecoverComponentRequest._();
  static $pb.GeneratedMessage $_createMessage() => RecoverComponentRequest._();
  @$core.override
  RecoverComponentRequest createEmptyInstance() => RecoverComponentRequest._();
  @$core.pragma('dart2js:noInline')
  static RecoverComponentRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RecoverComponentRequest>(
          RecoverComponentRequest.$_createMessage);
  static RecoverComponentRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get phoneId => $_getSZ(0);
  @$pb.TagNumber(1)
  set phoneId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPhoneId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPhoneId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(2)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRequestId() => $_clearField(2);

  @$pb.TagNumber(3)
  ComponentId get component => $_getN(2);
  @$pb.TagNumber(3)
  set component(ComponentId value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasComponent() => $_has(2);
  @$pb.TagNumber(3)
  void clearComponent() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get allowHotspotRestart => $_getBF(3);
  @$pb.TagNumber(4)
  set allowHotspotRestart($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAllowHotspotRestart() => $_has(3);
  @$pb.TagNumber(4)
  void clearAllowHotspotRestart() => $_clearField(4);
}

class ControlCommandResponse extends $pb.GeneratedMessage {
  factory ControlCommandResponse({
    $core.String? requestId,
    $core.bool? accepted,
    CommandStatus? status,
    $core.String? reason,
  }) {
    final result = ControlCommandResponse._();
    if (requestId != null) result.requestId = requestId;
    if (accepted != null) result.accepted = accepted;
    if (status != null) result.status = status;
    if (reason != null) result.reason = reason;
    return result;
  }

  ControlCommandResponse._();

  factory ControlCommandResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlCommandResponse()..mergeFromBuffer(data, registry);
  factory ControlCommandResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlCommandResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ControlCommandResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'pocketnet.v1'),
      createEmptyInstance: ControlCommandResponse.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOB(2, _omitFieldNames ? '' : 'accepted')
    ..aE<CommandStatus>(3, _omitFieldNames ? '' : 'status',
        enumValues: CommandStatus.values)
    ..aOS(4, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlCommandResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlCommandResponse copyWith(
          void Function(ControlCommandResponse) updates) =>
      super.copyWith((message) => updates(message as ControlCommandResponse))
          as ControlCommandResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ControlCommandResponse() / ControlCommandResponse.new instead')
  static ControlCommandResponse create() => ControlCommandResponse._();
  static $pb.GeneratedMessage $_createMessage() => ControlCommandResponse._();
  @$core.override
  ControlCommandResponse createEmptyInstance() => ControlCommandResponse._();
  @$core.pragma('dart2js:noInline')
  static ControlCommandResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ControlCommandResponse>(
          ControlCommandResponse.$_createMessage);
  static ControlCommandResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get accepted => $_getBF(1);
  @$pb.TagNumber(2)
  set accepted($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccepted() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccepted() => $_clearField(2);

  @$pb.TagNumber(3)
  CommandStatus get status => $_getN(2);
  @$pb.TagNumber(3)
  set status(CommandStatus value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasStatus() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatus() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get reason => $_getSZ(3);
  @$pb.TagNumber(4)
  set reason($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasReason() => $_has(3);
  @$pb.TagNumber(4)
  void clearReason() => $_clearField(4);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
