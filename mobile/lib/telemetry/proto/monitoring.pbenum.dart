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

import 'package:protobuf/protobuf.dart' as $pb;

class EventPriority extends $pb.ProtobufEnum {
  static const EventPriority P0 =
      EventPriority._(0, _omitEnumNames ? '' : 'P0');
  static const EventPriority P1 =
      EventPriority._(1, _omitEnumNames ? '' : 'P1');
  static const EventPriority P2 =
      EventPriority._(2, _omitEnumNames ? '' : 'P2');
  static const EventPriority P3 =
      EventPriority._(3, _omitEnumNames ? '' : 'P3');

  static const $core.List<EventPriority> values = <EventPriority>[
    P0,
    P1,
    P2,
    P3,
  ];

  static final $core.List<EventPriority?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static EventPriority? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EventPriority._(super.value, super.name);
}

class EventCategory extends $pb.ProtobufEnum {
  static const EventCategory EVENT_CATEGORY_UNSPECIFIED =
      EventCategory._(0, _omitEnumNames ? '' : 'EVENT_CATEGORY_UNSPECIFIED');
  static const EventCategory SECURITY =
      EventCategory._(1, _omitEnumNames ? '' : 'SECURITY');
  static const EventCategory DEVICE_HEALTH =
      EventCategory._(2, _omitEnumNames ? '' : 'DEVICE_HEALTH');
  static const EventCategory OBSERVATION =
      EventCategory._(3, _omitEnumNames ? '' : 'OBSERVATION');
  static const EventCategory DATA_QUALITY =
      EventCategory._(4, _omitEnumNames ? '' : 'DATA_QUALITY');

  static const $core.List<EventCategory> values = <EventCategory>[
    EVENT_CATEGORY_UNSPECIFIED,
    SECURITY,
    DEVICE_HEALTH,
    OBSERVATION,
    DATA_QUALITY,
  ];

  static final $core.List<EventCategory?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static EventCategory? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EventCategory._(super.value, super.name);
}

class RiskClass extends $pb.ProtobufEnum {
  static const RiskClass RISK_UNSPECIFIED =
      RiskClass._(0, _omitEnumNames ? '' : 'RISK_UNSPECIFIED');
  static const RiskClass INFO = RiskClass._(1, _omitEnumNames ? '' : 'INFO');
  static const RiskClass SUSPICIOUS =
      RiskClass._(2, _omitEnumNames ? '' : 'SUSPICIOUS');
  static const RiskClass HIGH = RiskClass._(3, _omitEnumNames ? '' : 'HIGH');
  static const RiskClass CRITICAL =
      RiskClass._(4, _omitEnumNames ? '' : 'CRITICAL');

  static const $core.List<RiskClass> values = <RiskClass>[
    RISK_UNSPECIFIED,
    INFO,
    SUSPICIOUS,
    HIGH,
    CRITICAL,
  ];

  static final $core.List<RiskClass?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static RiskClass? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RiskClass._(super.value, super.name);
}

class Confidence extends $pb.ProtobufEnum {
  static const Confidence CONFIDENCE_UNSPECIFIED =
      Confidence._(0, _omitEnumNames ? '' : 'CONFIDENCE_UNSPECIFIED');
  static const Confidence LIMITED =
      Confidence._(1, _omitEnumNames ? '' : 'LIMITED');
  static const Confidence CORROBORATED =
      Confidence._(2, _omitEnumNames ? '' : 'CORROBORATED');

  static const $core.List<Confidence> values = <Confidence>[
    CONFIDENCE_UNSPECIFIED,
    LIMITED,
    CORROBORATED,
  ];

  static final $core.List<Confidence?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static Confidence? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Confidence._(super.value, super.name);
}

class CaptureProfile extends $pb.ProtobufEnum {
  static const CaptureProfile CAPTURE_PROFILE_UNSPECIFIED =
      CaptureProfile._(0, _omitEnumNames ? '' : 'CAPTURE_PROFILE_UNSPECIFIED');
  static const CaptureProfile LIGHT =
      CaptureProfile._(1, _omitEnumNames ? '' : 'LIGHT');
  static const CaptureProfile BALANCED =
      CaptureProfile._(2, _omitEnumNames ? '' : 'BALANCED');
  static const CaptureProfile EXTENDED =
      CaptureProfile._(3, _omitEnumNames ? '' : 'EXTENDED');

  static const $core.List<CaptureProfile> values = <CaptureProfile>[
    CAPTURE_PROFILE_UNSPECIFIED,
    LIGHT,
    BALANCED,
    EXTENDED,
  ];

  static final $core.List<CaptureProfile?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static CaptureProfile? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CaptureProfile._(super.value, super.name);
}

class ResourceLevel extends $pb.ProtobufEnum {
  static const ResourceLevel RESOURCE_LEVEL_UNSPECIFIED =
      ResourceLevel._(0, _omitEnumNames ? '' : 'RESOURCE_LEVEL_UNSPECIFIED');
  static const ResourceLevel NORMAL =
      ResourceLevel._(1, _omitEnumNames ? '' : 'NORMAL');
  static const ResourceLevel LEVEL1_WARN =
      ResourceLevel._(2, _omitEnumNames ? '' : 'LEVEL1_WARN');
  static const ResourceLevel LEVEL2_FALLBACK =
      ResourceLevel._(3, _omitEnumNames ? '' : 'LEVEL2_FALLBACK');

  static const $core.List<ResourceLevel> values = <ResourceLevel>[
    RESOURCE_LEVEL_UNSPECIFIED,
    NORMAL,
    LEVEL1_WARN,
    LEVEL2_FALLBACK,
  ];

  static final $core.List<ResourceLevel?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ResourceLevel? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ResourceLevel._(super.value, super.name);
}

class ComponentId extends $pb.ProtobufEnum {
  static const ComponentId COMPONENT_UNSPECIFIED =
      ComponentId._(0, _omitEnumNames ? '' : 'COMPONENT_UNSPECIFIED');
  static const ComponentId MGMT_WIFI =
      ComponentId._(1, _omitEnumNames ? '' : 'MGMT_WIFI');
  static const ComponentId MONITOR_WIFI =
      ComponentId._(2, _omitEnumNames ? '' : 'MONITOR_WIFI');
  static const ComponentId BLE = ComponentId._(3, _omitEnumNames ? '' : 'BLE');
  static const ComponentId TELEMETRY_CONNECTION =
      ComponentId._(4, _omitEnumNames ? '' : 'TELEMETRY_CONNECTION');
  static const ComponentId ALERT_INPUT =
      ComponentId._(5, _omitEnumNames ? '' : 'ALERT_INPUT');

  static const $core.List<ComponentId> values = <ComponentId>[
    COMPONENT_UNSPECIFIED,
    MGMT_WIFI,
    MONITOR_WIFI,
    BLE,
    TELEMETRY_CONNECTION,
    ALERT_INPUT,
  ];

  static final $core.List<ComponentId?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static ComponentId? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ComponentId._(super.value, super.name);
}

class ComponentState extends $pb.ProtobufEnum {
  static const ComponentState COMPONENT_STATE_UNSPECIFIED =
      ComponentState._(0, _omitEnumNames ? '' : 'COMPONENT_STATE_UNSPECIFIED');
  static const ComponentState READY =
      ComponentState._(1, _omitEnumNames ? '' : 'READY');
  static const ComponentState IDLE =
      ComponentState._(2, _omitEnumNames ? '' : 'IDLE');
  static const ComponentState STARTING =
      ComponentState._(3, _omitEnumNames ? '' : 'STARTING');
  static const ComponentState DEGRADED =
      ComponentState._(4, _omitEnumNames ? '' : 'DEGRADED');
  static const ComponentState FAILED =
      ComponentState._(5, _omitEnumNames ? '' : 'FAILED');
  static const ComponentState UNKNOWN =
      ComponentState._(6, _omitEnumNames ? '' : 'UNKNOWN');

  static const $core.List<ComponentState> values = <ComponentState>[
    COMPONENT_STATE_UNSPECIFIED,
    READY,
    IDLE,
    STARTING,
    DEGRADED,
    FAILED,
    UNKNOWN,
  ];

  static final $core.List<ComponentState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static ComponentState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ComponentState._(super.value, super.name);
}

class ObservedDeviceKind extends $pb.ProtobufEnum {
  static const ObservedDeviceKind OBSERVED_KIND_UNSPECIFIED =
      ObservedDeviceKind._(
          0, _omitEnumNames ? '' : 'OBSERVED_KIND_UNSPECIFIED');
  static const ObservedDeviceKind AP =
      ObservedDeviceKind._(1, _omitEnumNames ? '' : 'AP');
  static const ObservedDeviceKind CLIENT =
      ObservedDeviceKind._(2, _omitEnumNames ? '' : 'CLIENT');

  static const $core.List<ObservedDeviceKind> values = <ObservedDeviceKind>[
    OBSERVED_KIND_UNSPECIFIED,
    AP,
    CLIENT,
  ];

  static final $core.List<ObservedDeviceKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static ObservedDeviceKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ObservedDeviceKind._(super.value, super.name);
}

class AssociationState extends $pb.ProtobufEnum {
  static const AssociationState ASSOCIATION_UNSPECIFIED =
      AssociationState._(0, _omitEnumNames ? '' : 'ASSOCIATION_UNSPECIFIED');
  static const AssociationState NOT_ESTABLISHED =
      AssociationState._(1, _omitEnumNames ? '' : 'NOT_ESTABLISHED');
  static const AssociationState CONFIRMED =
      AssociationState._(2, _omitEnumNames ? '' : 'CONFIRMED');

  static const $core.List<AssociationState> values = <AssociationState>[
    ASSOCIATION_UNSPECIFIED,
    NOT_ESTABLISHED,
    CONFIRMED,
  ];

  static final $core.List<AssociationState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static AssociationState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AssociationState._(super.value, super.name);
}

class TrafficStatus extends $pb.ProtobufEnum {
  static const TrafficStatus TRAFFIC_UNAVAILABLE =
      TrafficStatus._(0, _omitEnumNames ? '' : 'TRAFFIC_UNAVAILABLE');
  static const TrafficStatus TRAFFIC_WARMING_UP =
      TrafficStatus._(1, _omitEnumNames ? '' : 'TRAFFIC_WARMING_UP');
  static const TrafficStatus TRAFFIC_OBSERVED =
      TrafficStatus._(2, _omitEnumNames ? '' : 'TRAFFIC_OBSERVED');
  static const TrafficStatus TRAFFIC_PARTIAL =
      TrafficStatus._(3, _omitEnumNames ? '' : 'TRAFFIC_PARTIAL');
  static const TrafficStatus TRAFFIC_PROFILE_FILTERED =
      TrafficStatus._(4, _omitEnumNames ? '' : 'TRAFFIC_PROFILE_FILTERED');

  static const $core.List<TrafficStatus> values = <TrafficStatus>[
    TRAFFIC_UNAVAILABLE,
    TRAFFIC_WARMING_UP,
    TRAFFIC_OBSERVED,
    TRAFFIC_PARTIAL,
    TRAFFIC_PROFILE_FILTERED,
  ];

  static final $core.List<TrafficStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static TrafficStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TrafficStatus._(super.value, super.name);
}

class CommandStatus extends $pb.ProtobufEnum {
  static const CommandStatus COMMAND_STATUS_UNSPECIFIED =
      CommandStatus._(0, _omitEnumNames ? '' : 'COMMAND_STATUS_UNSPECIFIED');
  static const CommandStatus ACCEPTED =
      CommandStatus._(1, _omitEnumNames ? '' : 'ACCEPTED');
  static const CommandStatus REFUSED =
      CommandStatus._(2, _omitEnumNames ? '' : 'REFUSED');
  static const CommandStatus BUSY =
      CommandStatus._(3, _omitEnumNames ? '' : 'BUSY');
  static const CommandStatus UNSUPPORTED =
      CommandStatus._(4, _omitEnumNames ? '' : 'UNSUPPORTED');

  static const $core.List<CommandStatus> values = <CommandStatus>[
    COMMAND_STATUS_UNSPECIFIED,
    ACCEPTED,
    REFUSED,
    BUSY,
    UNSUPPORTED,
  ];

  static final $core.List<CommandStatus?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static CommandStatus? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CommandStatus._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
