// This is a generated file - do not edit.
//
// Generated from monitoring.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use eventPriorityDescriptor instead')
const EventPriority$json = {
  '1': 'EventPriority',
  '2': [
    {'1': 'P0', '2': 0},
    {'1': 'P1', '2': 1},
    {'1': 'P2', '2': 2},
    {'1': 'P3', '2': 3},
  ],
};

/// Descriptor for `EventPriority`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventPriorityDescriptor = $convert.base64Decode(
    'Cg1FdmVudFByaW9yaXR5EgYKAlAwEAASBgoCUDEQARIGCgJQMhACEgYKAlAzEAM=');

@$core.Deprecated('Use eventCategoryDescriptor instead')
const EventCategory$json = {
  '1': 'EventCategory',
  '2': [
    {'1': 'EVENT_CATEGORY_UNSPECIFIED', '2': 0},
    {'1': 'SECURITY', '2': 1},
    {'1': 'DEVICE_HEALTH', '2': 2},
    {'1': 'OBSERVATION', '2': 3},
    {'1': 'DATA_QUALITY', '2': 4},
  ],
};

/// Descriptor for `EventCategory`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventCategoryDescriptor = $convert.base64Decode(
    'Cg1FdmVudENhdGVnb3J5Eh4KGkVWRU5UX0NBVEVHT1JZX1VOU1BFQ0lGSUVEEAASDAoIU0VDVV'
    'JJVFkQARIRCg1ERVZJQ0VfSEVBTFRIEAISDwoLT0JTRVJWQVRJT04QAxIQCgxEQVRBX1FVQUxJ'
    'VFkQBA==');

@$core.Deprecated('Use riskClassDescriptor instead')
const RiskClass$json = {
  '1': 'RiskClass',
  '2': [
    {'1': 'RISK_UNSPECIFIED', '2': 0},
    {'1': 'INFO', '2': 1},
    {'1': 'SUSPICIOUS', '2': 2},
    {'1': 'HIGH', '2': 3},
    {'1': 'CRITICAL', '2': 4},
  ],
};

/// Descriptor for `RiskClass`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List riskClassDescriptor = $convert.base64Decode(
    'CglSaXNrQ2xhc3MSFAoQUklTS19VTlNQRUNJRklFRBAAEggKBElORk8QARIOCgpTVVNQSUNJT1'
    'VTEAISCAoESElHSBADEgwKCENSSVRJQ0FMEAQ=');

@$core.Deprecated('Use confidenceDescriptor instead')
const Confidence$json = {
  '1': 'Confidence',
  '2': [
    {'1': 'CONFIDENCE_UNSPECIFIED', '2': 0},
    {'1': 'LIMITED', '2': 1},
    {'1': 'CORROBORATED', '2': 2},
  ],
};

/// Descriptor for `Confidence`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List confidenceDescriptor = $convert.base64Decode(
    'CgpDb25maWRlbmNlEhoKFkNPTkZJREVOQ0VfVU5TUEVDSUZJRUQQABILCgdMSU1JVEVEEAESEA'
    'oMQ09SUk9CT1JBVEVEEAI=');

@$core.Deprecated('Use captureProfileDescriptor instead')
const CaptureProfile$json = {
  '1': 'CaptureProfile',
  '2': [
    {'1': 'CAPTURE_PROFILE_UNSPECIFIED', '2': 0},
    {'1': 'LIGHT', '2': 1},
    {'1': 'BALANCED', '2': 2},
    {'1': 'EXTENDED', '2': 3},
  ],
};

/// Descriptor for `CaptureProfile`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List captureProfileDescriptor = $convert.base64Decode(
    'Cg5DYXB0dXJlUHJvZmlsZRIfChtDQVBUVVJFX1BST0ZJTEVfVU5TUEVDSUZJRUQQABIJCgVMSU'
    'dIVBABEgwKCEJBTEFOQ0VEEAISDAoIRVhURU5ERUQQAw==');

@$core.Deprecated('Use resourceLevelDescriptor instead')
const ResourceLevel$json = {
  '1': 'ResourceLevel',
  '2': [
    {'1': 'RESOURCE_LEVEL_UNSPECIFIED', '2': 0},
    {'1': 'NORMAL', '2': 1},
    {'1': 'LEVEL1_WARN', '2': 2},
    {'1': 'LEVEL2_FALLBACK', '2': 3},
  ],
};

/// Descriptor for `ResourceLevel`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List resourceLevelDescriptor = $convert.base64Decode(
    'Cg1SZXNvdXJjZUxldmVsEh4KGlJFU09VUkNFX0xFVkVMX1VOU1BFQ0lGSUVEEAASCgoGTk9STU'
    'FMEAESDwoLTEVWRUwxX1dBUk4QAhITCg9MRVZFTDJfRkFMTEJBQ0sQAw==');

@$core.Deprecated('Use componentIdDescriptor instead')
const ComponentId$json = {
  '1': 'ComponentId',
  '2': [
    {'1': 'COMPONENT_UNSPECIFIED', '2': 0},
    {'1': 'MGMT_WIFI', '2': 1},
    {'1': 'MONITOR_WIFI', '2': 2},
    {'1': 'BLE', '2': 3},
    {'1': 'TELEMETRY_CONNECTION', '2': 4},
    {'1': 'ALERT_INPUT', '2': 5},
  ],
};

/// Descriptor for `ComponentId`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List componentIdDescriptor = $convert.base64Decode(
    'CgtDb21wb25lbnRJZBIZChVDT01QT05FTlRfVU5TUEVDSUZJRUQQABINCglNR01UX1dJRkkQAR'
    'IQCgxNT05JVE9SX1dJRkkQAhIHCgNCTEUQAxIYChRURUxFTUVUUllfQ09OTkVDVElPThAEEg8K'
    'C0FMRVJUX0lOUFVUEAU=');

@$core.Deprecated('Use componentStateDescriptor instead')
const ComponentState$json = {
  '1': 'ComponentState',
  '2': [
    {'1': 'COMPONENT_STATE_UNSPECIFIED', '2': 0},
    {'1': 'READY', '2': 1},
    {'1': 'IDLE', '2': 2},
    {'1': 'STARTING', '2': 3},
    {'1': 'DEGRADED', '2': 4},
    {'1': 'FAILED', '2': 5},
    {'1': 'UNKNOWN', '2': 6},
  ],
};

/// Descriptor for `ComponentState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List componentStateDescriptor = $convert.base64Decode(
    'Cg5Db21wb25lbnRTdGF0ZRIfChtDT01QT05FTlRfU1RBVEVfVU5TUEVDSUZJRUQQABIJCgVSRU'
    'FEWRABEggKBElETEUQAhIMCghTVEFSVElORxADEgwKCERFR1JBREVEEAQSCgoGRkFJTEVEEAUS'
    'CwoHVU5LTk9XThAG');

@$core.Deprecated('Use observedDeviceKindDescriptor instead')
const ObservedDeviceKind$json = {
  '1': 'ObservedDeviceKind',
  '2': [
    {'1': 'OBSERVED_KIND_UNSPECIFIED', '2': 0},
    {'1': 'AP', '2': 1},
    {'1': 'CLIENT', '2': 2},
  ],
};

/// Descriptor for `ObservedDeviceKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List observedDeviceKindDescriptor = $convert.base64Decode(
    'ChJPYnNlcnZlZERldmljZUtpbmQSHQoZT0JTRVJWRURfS0lORF9VTlNQRUNJRklFRBAAEgYKAk'
    'FQEAESCgoGQ0xJRU5UEAI=');

@$core.Deprecated('Use associationStateDescriptor instead')
const AssociationState$json = {
  '1': 'AssociationState',
  '2': [
    {'1': 'ASSOCIATION_UNSPECIFIED', '2': 0},
    {'1': 'NOT_ESTABLISHED', '2': 1},
    {'1': 'CONFIRMED', '2': 2},
  ],
};

/// Descriptor for `AssociationState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List associationStateDescriptor = $convert.base64Decode(
    'ChBBc3NvY2lhdGlvblN0YXRlEhsKF0FTU09DSUFUSU9OX1VOU1BFQ0lGSUVEEAASEwoPTk9UX0'
    'VTVEFCTElTSEVEEAESDQoJQ09ORklSTUVEEAI=');

@$core.Deprecated('Use trafficStatusDescriptor instead')
const TrafficStatus$json = {
  '1': 'TrafficStatus',
  '2': [
    {'1': 'TRAFFIC_UNAVAILABLE', '2': 0},
    {'1': 'TRAFFIC_WARMING_UP', '2': 1},
    {'1': 'TRAFFIC_OBSERVED', '2': 2},
    {'1': 'TRAFFIC_PARTIAL', '2': 3},
    {'1': 'TRAFFIC_PROFILE_FILTERED', '2': 4},
  ],
};

/// Descriptor for `TrafficStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List trafficStatusDescriptor = $convert.base64Decode(
    'Cg1UcmFmZmljU3RhdHVzEhcKE1RSQUZGSUNfVU5BVkFJTEFCTEUQABIWChJUUkFGRklDX1dBUk'
    '1JTkdfVVAQARIUChBUUkFGRklDX09CU0VSVkVEEAISEwoPVFJBRkZJQ19QQVJUSUFMEAMSHAoY'
    'VFJBRkZJQ19QUk9GSUxFX0ZJTFRFUkVEEAQ=');

@$core.Deprecated('Use commandStatusDescriptor instead')
const CommandStatus$json = {
  '1': 'CommandStatus',
  '2': [
    {'1': 'COMMAND_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'ACCEPTED', '2': 1},
    {'1': 'REFUSED', '2': 2},
    {'1': 'BUSY', '2': 3},
    {'1': 'UNSUPPORTED', '2': 4},
  ],
};

/// Descriptor for `CommandStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List commandStatusDescriptor = $convert.base64Decode(
    'Cg1Db21tYW5kU3RhdHVzEh4KGkNPTU1BTkRfU1RBVFVTX1VOU1BFQ0lGSUVEEAASDAoIQUNDRV'
    'BURUQQARILCgdSRUZVU0VEEAISCAoEQlVTWRADEg8KC1VOU1VQUE9SVEVEEAQ=');

@$core.Deprecated('Use subscribeRequestDescriptor instead')
const SubscribeRequest$json = {
  '1': 'SubscribeRequest',
  '2': [
    {'1': 'device_id', '3': 1, '4': 1, '5': 9, '10': 'deviceId'},
    {
      '1': 'last_event_sequence',
      '3': 2,
      '4': 1,
      '5': 4,
      '10': 'lastEventSequence'
    },
    {'1': 'last_boot_id', '3': 3, '4': 1, '5': 9, '10': 'lastBootId'},
    {'1': 'accepts_high_risk', '3': 4, '4': 1, '5': 8, '10': 'acceptsHighRisk'},
  ],
};

/// Descriptor for `SubscribeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List subscribeRequestDescriptor = $convert.base64Decode(
    'ChBTdWJzY3JpYmVSZXF1ZXN0EhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQSLgoTbGFzdF'
    '9ldmVudF9zZXF1ZW5jZRgCIAEoBFIRbGFzdEV2ZW50U2VxdWVuY2USIAoMbGFzdF9ib290X2lk'
    'GAMgASgJUgpsYXN0Qm9vdElkEioKEWFjY2VwdHNfaGlnaF9yaXNrGAQgASgIUg9hY2NlcHRzSG'
    'lnaFJpc2s=');

@$core.Deprecated('Use telemetryMessageDescriptor instead')
const TelemetryMessage$json = {
  '1': 'TelemetryMessage',
  '2': [
    {
      '1': 'snapshot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.MonitoringSnapshot',
      '9': 0,
      '10': 'snapshot'
    },
    {
      '1': 'event',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.MonitoringEvent',
      '9': 0,
      '10': 'event'
    },
    {
      '1': 'history_gap',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.HistoryGap',
      '9': 0,
      '10': 'historyGap'
    },
    {
      '1': 'high_risk',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.HighRiskEnvelope',
      '9': 0,
      '10': 'highRisk'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `TelemetryMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List telemetryMessageDescriptor = $convert.base64Decode(
    'ChBUZWxlbWV0cnlNZXNzYWdlEj4KCHNuYXBzaG90GAEgASgLMiAucG9ja2V0bmV0LnYxLk1vbm'
    'l0b3JpbmdTbmFwc2hvdEgAUghzbmFwc2hvdBI1CgVldmVudBgCIAEoCzIdLnBvY2tldG5ldC52'
    'MS5Nb25pdG9yaW5nRXZlbnRIAFIFZXZlbnQSOwoLaGlzdG9yeV9nYXAYAyABKAsyGC5wb2NrZX'
    'RuZXQudjEuSGlzdG9yeUdhcEgAUgpoaXN0b3J5R2FwEj0KCWhpZ2hfcmlzaxgEIAEoCzIeLnBv'
    'Y2tldG5ldC52MS5IaWdoUmlza0VudmVsb3BlSABSCGhpZ2hSaXNrQgkKB3BheWxvYWQ=');

@$core.Deprecated('Use historyGapDescriptor instead')
const HistoryGap$json = {
  '1': 'HistoryGap',
  '2': [
    {'1': 'boot_id', '3': 1, '4': 1, '5': 9, '10': 'bootId'},
    {
      '1': 'through_event_sequence',
      '3': 2,
      '4': 1,
      '5': 4,
      '10': 'throughEventSequence'
    },
    {'1': 'reason', '3': 3, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `HistoryGap`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List historyGapDescriptor = $convert.base64Decode(
    'CgpIaXN0b3J5R2FwEhcKB2Jvb3RfaWQYASABKAlSBmJvb3RJZBI0ChZ0aHJvdWdoX2V2ZW50X3'
    'NlcXVlbmNlGAIgASgEUhR0aHJvdWdoRXZlbnRTZXF1ZW5jZRIWCgZyZWFzb24YAyABKAlSBnJl'
    'YXNvbg==');

@$core.Deprecated('Use monitoringSnapshotDescriptor instead')
const MonitoringSnapshot$json = {
  '1': 'MonitoringSnapshot',
  '2': [
    {'1': 'boot_id', '3': 1, '4': 1, '5': 9, '10': 'bootId'},
    {'1': 'sequence', '3': 2, '4': 1, '5': 4, '10': 'sequence'},
    {'1': 'timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'timestampMs'},
    {
      '1': 'system',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.SystemMetrics',
      '10': 'system'
    },
    {
      '1': 'capture',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.CaptureMetrics',
      '10': 'capture'
    },
    {
      '1': 'wireless',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.WirelessSummary',
      '10': 'wireless'
    },
    {'1': 'schema_version', '3': 7, '4': 1, '5': 13, '10': 'schemaVersion'},
    {
      '1': 'latest_event_sequence',
      '3': 8,
      '4': 1,
      '5': 4,
      '10': 'latestEventSequence'
    },
    {
      '1': 'delivery',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.DeliveryMetrics',
      '10': 'delivery'
    },
    {
      '1': 'device_health',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.DeviceHealth',
      '10': 'deviceHealth'
    },
    {
      '1': 'capture_policy',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.CapturePolicyStatus',
      '10': 'capturePolicy'
    },
    {
      '1': 'observation_session',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.ObservationSession',
      '10': 'observationSession'
    },
    {
      '1': 'high_risk_delivery',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.HighRiskDeliveryStatus',
      '10': 'highRiskDelivery'
    },
    {
      '1': 'capability_version',
      '3': 14,
      '4': 1,
      '5': 13,
      '10': 'capabilityVersion'
    },
    {
      '1': 'supported_features',
      '3': 15,
      '4': 3,
      '5': 9,
      '10': 'supportedFeatures'
    },
    {'1': 'device_boot_id', '3': 16, '4': 1, '5': 9, '10': 'deviceBootId'},
    {
      '1': 'resource_pressure',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.ResourcePressureStatus',
      '10': 'resourcePressure'
    },
  ],
};

/// Descriptor for `MonitoringSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List monitoringSnapshotDescriptor = $convert.base64Decode(
    'ChJNb25pdG9yaW5nU25hcHNob3QSFwoHYm9vdF9pZBgBIAEoCVIGYm9vdElkEhoKCHNlcXVlbm'
    'NlGAIgASgEUghzZXF1ZW5jZRIhCgx0aW1lc3RhbXBfbXMYAyABKANSC3RpbWVzdGFtcE1zEjMK'
    'BnN5c3RlbRgEIAEoCzIbLnBvY2tldG5ldC52MS5TeXN0ZW1NZXRyaWNzUgZzeXN0ZW0SNgoHY2'
    'FwdHVyZRgFIAEoCzIcLnBvY2tldG5ldC52MS5DYXB0dXJlTWV0cmljc1IHY2FwdHVyZRI5Cgh3'
    'aXJlbGVzcxgGIAEoCzIdLnBvY2tldG5ldC52MS5XaXJlbGVzc1N1bW1hcnlSCHdpcmVsZXNzEi'
    'UKDnNjaGVtYV92ZXJzaW9uGAcgASgNUg1zY2hlbWFWZXJzaW9uEjIKFWxhdGVzdF9ldmVudF9z'
    'ZXF1ZW5jZRgIIAEoBFITbGF0ZXN0RXZlbnRTZXF1ZW5jZRI5CghkZWxpdmVyeRgJIAEoCzIdLn'
    'BvY2tldG5ldC52MS5EZWxpdmVyeU1ldHJpY3NSCGRlbGl2ZXJ5Ej8KDWRldmljZV9oZWFsdGgY'
    'CiABKAsyGi5wb2NrZXRuZXQudjEuRGV2aWNlSGVhbHRoUgxkZXZpY2VIZWFsdGgSSAoOY2FwdH'
    'VyZV9wb2xpY3kYCyABKAsyIS5wb2NrZXRuZXQudjEuQ2FwdHVyZVBvbGljeVN0YXR1c1INY2Fw'
    'dHVyZVBvbGljeRJRChNvYnNlcnZhdGlvbl9zZXNzaW9uGAwgASgLMiAucG9ja2V0bmV0LnYxLk'
    '9ic2VydmF0aW9uU2Vzc2lvblISb2JzZXJ2YXRpb25TZXNzaW9uElIKEmhpZ2hfcmlza19kZWxp'
    'dmVyeRgNIAEoCzIkLnBvY2tldG5ldC52MS5IaWdoUmlza0RlbGl2ZXJ5U3RhdHVzUhBoaWdoUm'
    'lza0RlbGl2ZXJ5Ei0KEmNhcGFiaWxpdHlfdmVyc2lvbhgOIAEoDVIRY2FwYWJpbGl0eVZlcnNp'
    'b24SLQoSc3VwcG9ydGVkX2ZlYXR1cmVzGA8gAygJUhFzdXBwb3J0ZWRGZWF0dXJlcxIkCg5kZX'
    'ZpY2VfYm9vdF9pZBgQIAEoCVIMZGV2aWNlQm9vdElkElEKEXJlc291cmNlX3ByZXNzdXJlGBEg'
    'ASgLMiQucG9ja2V0bmV0LnYxLlJlc291cmNlUHJlc3N1cmVTdGF0dXNSEHJlc291cmNlUHJlc3'
    'N1cmU=');

@$core.Deprecated('Use systemMetricsDescriptor instead')
const SystemMetrics$json = {
  '1': 'SystemMetrics',
  '2': [
    {'1': 'cpu_usage', '3': 1, '4': 1, '5': 2, '10': 'cpuUsage'},
    {
      '1': 'memory_total_bytes',
      '3': 2,
      '4': 1,
      '5': 4,
      '10': 'memoryTotalBytes'
    },
    {
      '1': 'memory_available_bytes',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'memoryAvailableBytes'
    },
    {'1': 'temperature_c', '3': 4, '4': 1, '5': 2, '10': 'temperatureC'},
    {
      '1': 'cpu_psi_some_avg10',
      '3': 5,
      '4': 1,
      '5': 2,
      '10': 'cpuPsiSomeAvg10'
    },
    {
      '1': 'memory_psi_some_avg10',
      '3': 6,
      '4': 1,
      '5': 2,
      '10': 'memoryPsiSomeAvg10'
    },
    {'1': 'swap_total_bytes', '3': 7, '4': 1, '5': 4, '10': 'swapTotalBytes'},
    {'1': 'swap_free_bytes', '3': 8, '4': 1, '5': 4, '10': 'swapFreeBytes'},
    {'1': 'cpu_frequency_mhz', '3': 9, '4': 1, '5': 2, '10': 'cpuFrequencyMhz'},
    {
      '1': 'disk_read_bytes_per_second',
      '3': 10,
      '4': 1,
      '5': 1,
      '10': 'diskReadBytesPerSecond'
    },
    {
      '1': 'disk_write_bytes_per_second',
      '3': 11,
      '4': 1,
      '5': 1,
      '10': 'diskWriteBytesPerSecond'
    },
    {
      '1': 'disk_reads_per_second',
      '3': 12,
      '4': 1,
      '5': 1,
      '10': 'diskReadsPerSecond'
    },
    {
      '1': 'disk_writes_per_second',
      '3': 13,
      '4': 1,
      '5': 1,
      '10': 'diskWritesPerSecond'
    },
    {
      '1': 'disk_busy_ms_per_second',
      '3': 14,
      '4': 1,
      '5': 1,
      '10': 'diskBusyMsPerSecond'
    },
    {
      '1': 'cpu_pressure',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.Pressure',
      '10': 'cpuPressure'
    },
    {
      '1': 'memory_pressure',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.Pressure',
      '10': 'memoryPressure'
    },
    {
      '1': 'io_pressure',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.Pressure',
      '10': 'ioPressure'
    },
    {'1': 'sampled_at_ms', '3': 18, '4': 1, '5': 3, '10': 'sampledAtMs'},
    {
      '1': 'memory_used_bytes',
      '3': 19,
      '4': 1,
      '5': 4,
      '10': 'memoryUsedBytes'
    },
  ],
};

/// Descriptor for `SystemMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List systemMetricsDescriptor = $convert.base64Decode(
    'Cg1TeXN0ZW1NZXRyaWNzEhsKCWNwdV91c2FnZRgBIAEoAlIIY3B1VXNhZ2USLAoSbWVtb3J5X3'
    'RvdGFsX2J5dGVzGAIgASgEUhBtZW1vcnlUb3RhbEJ5dGVzEjQKFm1lbW9yeV9hdmFpbGFibGVf'
    'Ynl0ZXMYAyABKARSFG1lbW9yeUF2YWlsYWJsZUJ5dGVzEiMKDXRlbXBlcmF0dXJlX2MYBCABKA'
    'JSDHRlbXBlcmF0dXJlQxIrChJjcHVfcHNpX3NvbWVfYXZnMTAYBSABKAJSD2NwdVBzaVNvbWVB'
    'dmcxMBIxChVtZW1vcnlfcHNpX3NvbWVfYXZnMTAYBiABKAJSEm1lbW9yeVBzaVNvbWVBdmcxMB'
    'IoChBzd2FwX3RvdGFsX2J5dGVzGAcgASgEUg5zd2FwVG90YWxCeXRlcxImCg9zd2FwX2ZyZWVf'
    'Ynl0ZXMYCCABKARSDXN3YXBGcmVlQnl0ZXMSKgoRY3B1X2ZyZXF1ZW5jeV9taHoYCSABKAJSD2'
    'NwdUZyZXF1ZW5jeU1oehI6ChpkaXNrX3JlYWRfYnl0ZXNfcGVyX3NlY29uZBgKIAEoAVIWZGlz'
    'a1JlYWRCeXRlc1BlclNlY29uZBI8ChtkaXNrX3dyaXRlX2J5dGVzX3Blcl9zZWNvbmQYCyABKA'
    'FSF2Rpc2tXcml0ZUJ5dGVzUGVyU2Vjb25kEjEKFWRpc2tfcmVhZHNfcGVyX3NlY29uZBgMIAEo'
    'AVISZGlza1JlYWRzUGVyU2Vjb25kEjMKFmRpc2tfd3JpdGVzX3Blcl9zZWNvbmQYDSABKAFSE2'
    'Rpc2tXcml0ZXNQZXJTZWNvbmQSNAoXZGlza19idXN5X21zX3Blcl9zZWNvbmQYDiABKAFSE2Rp'
    'c2tCdXN5TXNQZXJTZWNvbmQSOQoMY3B1X3ByZXNzdXJlGA8gASgLMhYucG9ja2V0bmV0LnYxLl'
    'ByZXNzdXJlUgtjcHVQcmVzc3VyZRI/Cg9tZW1vcnlfcHJlc3N1cmUYECABKAsyFi5wb2NrZXRu'
    'ZXQudjEuUHJlc3N1cmVSDm1lbW9yeVByZXNzdXJlEjcKC2lvX3ByZXNzdXJlGBEgASgLMhYucG'
    '9ja2V0bmV0LnYxLlByZXNzdXJlUgppb1ByZXNzdXJlEiIKDXNhbXBsZWRfYXRfbXMYEiABKANS'
    'C3NhbXBsZWRBdE1zEioKEW1lbW9yeV91c2VkX2J5dGVzGBMgASgEUg9tZW1vcnlVc2VkQnl0ZX'
    'M=');

@$core.Deprecated('Use pressureDescriptor instead')
const Pressure$json = {
  '1': 'Pressure',
  '2': [
    {'1': 'some_avg10', '3': 1, '4': 1, '5': 2, '10': 'someAvg10'},
    {'1': 'some_avg60', '3': 2, '4': 1, '5': 2, '10': 'someAvg60'},
    {'1': 'full_avg10', '3': 3, '4': 1, '5': 2, '10': 'fullAvg10'},
    {'1': 'full_avg60', '3': 4, '4': 1, '5': 2, '10': 'fullAvg60'},
  ],
};

/// Descriptor for `Pressure`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pressureDescriptor = $convert.base64Decode(
    'CghQcmVzc3VyZRIdCgpzb21lX2F2ZzEwGAEgASgCUglzb21lQXZnMTASHQoKc29tZV9hdmc2MB'
    'gCIAEoAlIJc29tZUF2ZzYwEh0KCmZ1bGxfYXZnMTAYAyABKAJSCWZ1bGxBdmcxMBIdCgpmdWxs'
    'X2F2ZzYwGAQgASgCUglmdWxsQXZnNjA=');

@$core.Deprecated('Use captureMetricsDescriptor instead')
const CaptureMetrics$json = {
  '1': 'CaptureMetrics',
  '2': [
    {'1': 'kismet_running', '3': 1, '4': 1, '5': 8, '10': 'kismetRunning'},
    {
      '1': 'datasource_running',
      '3': 2,
      '4': 1,
      '5': 8,
      '10': 'datasourceRunning'
    },
    {'1': 'datasource_state', '3': 3, '4': 1, '5': 9, '10': 'datasourceState'},
    {
      '1': 'packets_per_second',
      '3': 4,
      '4': 1,
      '5': 4,
      '10': 'packetsPerSecond'
    },
    {
      '1': 'processed_packets_per_second',
      '3': 5,
      '4': 1,
      '5': 4,
      '10': 'processedPacketsPerSecond'
    },
    {'1': 'backlog', '3': 6, '4': 1, '5': 4, '10': 'backlog'},
    {'1': 'dropped_packets', '3': 7, '4': 1, '5': 4, '10': 'droppedPackets'},
    {'1': 'coverage', '3': 8, '4': 1, '5': 9, '10': 'coverage'},
    {'1': 'sampled_at_ms', '3': 9, '4': 1, '5': 3, '10': 'sampledAtMs'},
    {'1': 'reason', '3': 10, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'current_channel', '3': 11, '4': 1, '5': 9, '10': 'currentChannel'},
    {
      '1': 'datasource_paused',
      '3': 12,
      '4': 1,
      '5': 8,
      '10': 'datasourcePaused'
    },
    {'1': 'datasource_error', '3': 13, '4': 1, '5': 8, '10': 'datasourceError'},
    {'1': 'tracked_devices', '3': 14, '4': 1, '5': 4, '10': 'trackedDevices'},
    {
      '1': 'packet_statistics_source',
      '3': 15,
      '4': 1,
      '5': 9,
      '10': 'packetStatisticsSource'
    },
    {'1': 'datasource_uuid', '3': 16, '4': 1, '5': 9, '10': 'datasourceUuid'},
  ],
};

/// Descriptor for `CaptureMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List captureMetricsDescriptor = $convert.base64Decode(
    'Cg5DYXB0dXJlTWV0cmljcxIlCg5raXNtZXRfcnVubmluZxgBIAEoCFINa2lzbWV0UnVubmluZx'
    'ItChJkYXRhc291cmNlX3J1bm5pbmcYAiABKAhSEWRhdGFzb3VyY2VSdW5uaW5nEikKEGRhdGFz'
    'b3VyY2Vfc3RhdGUYAyABKAlSD2RhdGFzb3VyY2VTdGF0ZRIsChJwYWNrZXRzX3Blcl9zZWNvbm'
    'QYBCABKARSEHBhY2tldHNQZXJTZWNvbmQSPwoccHJvY2Vzc2VkX3BhY2tldHNfcGVyX3NlY29u'
    'ZBgFIAEoBFIZcHJvY2Vzc2VkUGFja2V0c1BlclNlY29uZBIYCgdiYWNrbG9nGAYgASgEUgdiYW'
    'NrbG9nEicKD2Ryb3BwZWRfcGFja2V0cxgHIAEoBFIOZHJvcHBlZFBhY2tldHMSGgoIY292ZXJh'
    'Z2UYCCABKAlSCGNvdmVyYWdlEiIKDXNhbXBsZWRfYXRfbXMYCSABKANSC3NhbXBsZWRBdE1zEh'
    'YKBnJlYXNvbhgKIAEoCVIGcmVhc29uEicKD2N1cnJlbnRfY2hhbm5lbBgLIAEoCVIOY3VycmVu'
    'dENoYW5uZWwSKwoRZGF0YXNvdXJjZV9wYXVzZWQYDCABKAhSEGRhdGFzb3VyY2VQYXVzZWQSKQ'
    'oQZGF0YXNvdXJjZV9lcnJvchgNIAEoCFIPZGF0YXNvdXJjZUVycm9yEicKD3RyYWNrZWRfZGV2'
    'aWNlcxgOIAEoBFIOdHJhY2tlZERldmljZXMSOAoYcGFja2V0X3N0YXRpc3RpY3Nfc291cmNlGA'
    '8gASgJUhZwYWNrZXRTdGF0aXN0aWNzU291cmNlEicKD2RhdGFzb3VyY2VfdXVpZBgQIAEoCVIO'
    'ZGF0YXNvdXJjZVV1aWQ=');

@$core.Deprecated('Use wirelessSummaryDescriptor instead')
const WirelessSummary$json = {
  '1': 'WirelessSummary',
  '2': [
    {'1': 'ap_count', '3': 1, '4': 1, '5': 13, '10': 'apCount'},
    {'1': 'client_count', '3': 2, '4': 1, '5': 13, '10': 'clientCount'},
    {
      '1': 'priority_aps',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.pocketnet.v1.PriorityAP',
      '10': 'priorityAps'
    },
    {'1': 'truncated', '3': 4, '4': 1, '5': 8, '10': 'truncated'},
    {'1': 'sampled_at_ms', '3': 5, '4': 1, '5': 3, '10': 'sampledAtMs'},
    {'1': 'coverage', '3': 6, '4': 1, '5': 9, '10': 'coverage'},
  ],
};

/// Descriptor for `WirelessSummary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wirelessSummaryDescriptor = $convert.base64Decode(
    'Cg9XaXJlbGVzc1N1bW1hcnkSGQoIYXBfY291bnQYASABKA1SB2FwQ291bnQSIQoMY2xpZW50X2'
    'NvdW50GAIgASgNUgtjbGllbnRDb3VudBI7Cgxwcmlvcml0eV9hcHMYAyADKAsyGC5wb2NrZXRu'
    'ZXQudjEuUHJpb3JpdHlBUFILcHJpb3JpdHlBcHMSHAoJdHJ1bmNhdGVkGAQgASgIUgl0cnVuY2'
    'F0ZWQSIgoNc2FtcGxlZF9hdF9tcxgFIAEoA1ILc2FtcGxlZEF0TXMSGgoIY292ZXJhZ2UYBiAB'
    'KAlSCGNvdmVyYWdl');

@$core.Deprecated('Use priorityAPDescriptor instead')
const PriorityAP$json = {
  '1': 'PriorityAP',
  '2': [
    {'1': 'bssid', '3': 1, '4': 1, '5': 9, '10': 'bssid'},
    {'1': 'ssid', '3': 2, '4': 1, '5': 9, '10': 'ssid'},
    {'1': 'channel', '3': 3, '4': 1, '5': 9, '10': 'channel'},
    {'1': 'rssi_dbm', '3': 4, '4': 1, '5': 2, '10': 'rssiDbm'},
    {'1': 'security', '3': 5, '4': 1, '5': 9, '10': 'security'},
    {'1': 'frequency_khz', '3': 6, '4': 1, '5': 4, '10': 'frequencyKhz'},
    {'1': 'first_seen_ms', '3': 7, '4': 1, '5': 3, '10': 'firstSeenMs'},
    {'1': 'last_seen_ms', '3': 8, '4': 1, '5': 3, '10': 'lastSeenMs'},
  ],
};

/// Descriptor for `PriorityAP`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List priorityAPDescriptor = $convert.base64Decode(
    'CgpQcmlvcml0eUFQEhQKBWJzc2lkGAEgASgJUgVic3NpZBISCgRzc2lkGAIgASgJUgRzc2lkEh'
    'gKB2NoYW5uZWwYAyABKAlSB2NoYW5uZWwSGQoIcnNzaV9kYm0YBCABKAJSB3Jzc2lEYm0SGgoI'
    'c2VjdXJpdHkYBSABKAlSCHNlY3VyaXR5EiMKDWZyZXF1ZW5jeV9raHoYBiABKARSDGZyZXF1ZW'
    '5jeUtoehIiCg1maXJzdF9zZWVuX21zGAcgASgDUgtmaXJzdFNlZW5NcxIgCgxsYXN0X3NlZW5f'
    'bXMYCCABKANSCmxhc3RTZWVuTXM=');

@$core.Deprecated('Use monitoringEventDescriptor instead')
const MonitoringEvent$json = {
  '1': 'MonitoringEvent',
  '2': [
    {'1': 'boot_id', '3': 1, '4': 1, '5': 9, '10': 'bootId'},
    {'1': 'event_id', '3': 2, '4': 1, '5': 9, '10': 'eventId'},
    {'1': 'sequence', '3': 3, '4': 1, '5': 4, '10': 'sequence'},
    {'1': 'timestamp_ms', '3': 4, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'event_type', '3': 5, '4': 1, '5': 9, '10': 'eventType'},
    {
      '1': 'priority',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.EventPriority',
      '10': 'priority'
    },
    {'1': 'source', '3': 7, '4': 1, '5': 9, '10': 'source'},
    {'1': 'bssid', '3': 8, '4': 1, '5': 9, '10': 'bssid'},
    {'1': 'description', '3': 9, '4': 1, '5': 9, '10': 'description'},
    {'1': 'evidence_id', '3': 10, '4': 1, '5': 9, '10': 'evidenceId'},
    {'1': 'occurrences', '3': 11, '4': 1, '5': 13, '10': 'occurrences'},
    {
      '1': 'event_category',
      '3': 12,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.EventCategory',
      '10': 'eventCategory'
    },
    {
      '1': 'risk_class',
      '3': 13,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.RiskClass',
      '10': 'riskClass'
    },
    {
      '1': 'confidence',
      '3': 14,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.Confidence',
      '10': 'confidence'
    },
    {'1': 'source_scope', '3': 15, '4': 1, '5': 9, '10': 'sourceScope'},
    {'1': 'summary', '3': 16, '4': 1, '5': 9, '10': 'summary'},
    {'1': 'observed_at_ms', '3': 17, '4': 1, '5': 3, '10': 'observedAtMs'},
  ],
};

/// Descriptor for `MonitoringEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List monitoringEventDescriptor = $convert.base64Decode(
    'Cg9Nb25pdG9yaW5nRXZlbnQSFwoHYm9vdF9pZBgBIAEoCVIGYm9vdElkEhkKCGV2ZW50X2lkGA'
    'IgASgJUgdldmVudElkEhoKCHNlcXVlbmNlGAMgASgEUghzZXF1ZW5jZRIhCgx0aW1lc3RhbXBf'
    'bXMYBCABKANSC3RpbWVzdGFtcE1zEh0KCmV2ZW50X3R5cGUYBSABKAlSCWV2ZW50VHlwZRI3Cg'
    'hwcmlvcml0eRgGIAEoDjIbLnBvY2tldG5ldC52MS5FdmVudFByaW9yaXR5Ughwcmlvcml0eRIW'
    'CgZzb3VyY2UYByABKAlSBnNvdXJjZRIUCgVic3NpZBgIIAEoCVIFYnNzaWQSIAoLZGVzY3JpcH'
    'Rpb24YCSABKAlSC2Rlc2NyaXB0aW9uEh8KC2V2aWRlbmNlX2lkGAogASgJUgpldmlkZW5jZUlk'
    'EiAKC29jY3VycmVuY2VzGAsgASgNUgtvY2N1cnJlbmNlcxJCCg5ldmVudF9jYXRlZ29yeRgMIA'
    'EoDjIbLnBvY2tldG5ldC52MS5FdmVudENhdGVnb3J5Ug1ldmVudENhdGVnb3J5EjYKCnJpc2tf'
    'Y2xhc3MYDSABKA4yFy5wb2NrZXRuZXQudjEuUmlza0NsYXNzUglyaXNrQ2xhc3MSOAoKY29uZm'
    'lkZW5jZRgOIAEoDjIYLnBvY2tldG5ldC52MS5Db25maWRlbmNlUgpjb25maWRlbmNlEiEKDHNv'
    'dXJjZV9zY29wZRgPIAEoCVILc291cmNlU2NvcGUSGAoHc3VtbWFyeRgQIAEoCVIHc3VtbWFyeR'
    'IkCg5vYnNlcnZlZF9hdF9tcxgRIAEoA1IMb2JzZXJ2ZWRBdE1z');

@$core.Deprecated('Use deliveryMetricsDescriptor instead')
const DeliveryMetrics$json = {
  '1': 'DeliveryMetrics',
  '2': [
    {'1': 'dropped_events', '3': 1, '4': 1, '5': 4, '10': 'droppedEvents'},
    {'1': 'merged_events', '3': 2, '4': 1, '5': 4, '10': 'mergedEvents'},
    {'1': 'pending_events', '3': 3, '4': 1, '5': 13, '10': 'pendingEvents'},
  ],
};

/// Descriptor for `DeliveryMetrics`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deliveryMetricsDescriptor = $convert.base64Decode(
    'Cg9EZWxpdmVyeU1ldHJpY3MSJQoOZHJvcHBlZF9ldmVudHMYASABKARSDWRyb3BwZWRFdmVudH'
    'MSIwoNbWVyZ2VkX2V2ZW50cxgCIAEoBFIMbWVyZ2VkRXZlbnRzEiUKDnBlbmRpbmdfZXZlbnRz'
    'GAMgASgNUg1wZW5kaW5nRXZlbnRz');

@$core.Deprecated('Use highRiskEnvelopeDescriptor instead')
const HighRiskEnvelope$json = {
  '1': 'HighRiskEnvelope',
  '2': [
    {'1': 'durable_id', '3': 1, '4': 1, '5': 9, '10': 'durableId'},
    {
      '1': 'event',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.MonitoringEvent',
      '10': 'event'
    },
    {'1': 'ttl_seconds', '3': 3, '4': 1, '5': 13, '10': 'ttlSeconds'},
    {'1': 'enqueued_wall_ms', '3': 4, '4': 1, '5': 3, '10': 'enqueuedWallMs'},
  ],
};

/// Descriptor for `HighRiskEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List highRiskEnvelopeDescriptor = $convert.base64Decode(
    'ChBIaWdoUmlza0VudmVsb3BlEh0KCmR1cmFibGVfaWQYASABKAlSCWR1cmFibGVJZBIzCgVldm'
    'VudBgCIAEoCzIdLnBvY2tldG5ldC52MS5Nb25pdG9yaW5nRXZlbnRSBWV2ZW50Eh8KC3R0bF9z'
    'ZWNvbmRzGAMgASgNUgp0dGxTZWNvbmRzEigKEGVucXVldWVkX3dhbGxfbXMYBCABKANSDmVucX'
    'VldWVkV2FsbE1z');

@$core.Deprecated('Use ackHighRiskRequestDescriptor instead')
const AckHighRiskRequest$json = {
  '1': 'AckHighRiskRequest',
  '2': [
    {'1': 'phone_id', '3': 1, '4': 1, '5': 9, '10': 'phoneId'},
    {'1': 'durable_id', '3': 2, '4': 1, '5': 9, '10': 'durableId'},
  ],
};

/// Descriptor for `AckHighRiskRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackHighRiskRequestDescriptor = $convert.base64Decode(
    'ChJBY2tIaWdoUmlza1JlcXVlc3QSGQoIcGhvbmVfaWQYASABKAlSB3Bob25lSWQSHQoKZHVyYW'
    'JsZV9pZBgCIAEoCVIJZHVyYWJsZUlk');

@$core.Deprecated('Use ackHighRiskResponseDescriptor instead')
const AckHighRiskResponse$json = {
  '1': 'AckHighRiskResponse',
  '2': [
    {'1': 'result', '3': 1, '4': 1, '5': 9, '10': 'result'},
  ],
};

/// Descriptor for `AckHighRiskResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ackHighRiskResponseDescriptor =
    $convert.base64Decode(
        'ChNBY2tIaWdoUmlza1Jlc3BvbnNlEhYKBnJlc3VsdBgBIAEoCVIGcmVzdWx0');

@$core.Deprecated('Use capturePolicyStatusDescriptor instead')
const CapturePolicyStatus$json = {
  '1': 'CapturePolicyStatus',
  '2': [
    {'1': 'requested', '3': 1, '4': 1, '5': 9, '10': 'requested'},
    {'1': 'actual', '3': 2, '4': 1, '5': 9, '10': 'actual'},
    {'1': 'phase', '3': 3, '4': 1, '5': 9, '10': 'phase'},
    {'1': 'reason', '3': 4, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'pressure_forced', '3': 5, '4': 1, '5': 8, '10': 'pressureForced'},
  ],
};

/// Descriptor for `CapturePolicyStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List capturePolicyStatusDescriptor = $convert.base64Decode(
    'ChNDYXB0dXJlUG9saWN5U3RhdHVzEhwKCXJlcXVlc3RlZBgBIAEoCVIJcmVxdWVzdGVkEhYKBm'
    'FjdHVhbBgCIAEoCVIGYWN0dWFsEhQKBXBoYXNlGAMgASgJUgVwaGFzZRIWCgZyZWFzb24YBCAB'
    'KAlSBnJlYXNvbhInCg9wcmVzc3VyZV9mb3JjZWQYBSABKAhSDnByZXNzdXJlRm9yY2Vk');

@$core.Deprecated('Use observationSessionDescriptor instead')
const ObservationSession$json = {
  '1': 'ObservationSession',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'active', '3': 2, '4': 1, '5': 8, '10': 'active'},
    {
      '1': 'continuous_active_ms',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'continuousActiveMs'
    },
    {'1': 'reset_reason', '3': 4, '4': 1, '5': 9, '10': 'resetReason'},
  ],
};

/// Descriptor for `ObservationSession`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List observationSessionDescriptor = $convert.base64Decode(
    'ChJPYnNlcnZhdGlvblNlc3Npb24SHQoKc2Vzc2lvbl9pZBgBIAEoCVIJc2Vzc2lvbklkEhYKBm'
    'FjdGl2ZRgCIAEoCFIGYWN0aXZlEjAKFGNvbnRpbnVvdXNfYWN0aXZlX21zGAMgASgEUhJjb250'
    'aW51b3VzQWN0aXZlTXMSIQoMcmVzZXRfcmVhc29uGAQgASgJUgtyZXNldFJlYXNvbg==');

@$core.Deprecated('Use highRiskDeliveryStatusDescriptor instead')
const HighRiskDeliveryStatus$json = {
  '1': 'HighRiskDeliveryStatus',
  '2': [
    {'1': 'pending_count', '3': 1, '4': 1, '5': 13, '10': 'pendingCount'},
    {'1': 'pending_bytes', '3': 2, '4': 1, '5': 4, '10': 'pendingBytes'},
    {'1': 'acked_count', '3': 3, '4': 1, '5': 4, '10': 'ackedCount'},
    {'1': 'expired_count', '3': 4, '4': 1, '5': 4, '10': 'expiredCount'},
    {
      '1': 'overflow_evicted_count',
      '3': 5,
      '4': 1,
      '5': 4,
      '10': 'overflowEvictedCount'
    },
    {
      '1': 'storage_error_count',
      '3': 6,
      '4': 1,
      '5': 4,
      '10': 'storageErrorCount'
    },
    {
      '1': 'overflow_rejected_count',
      '3': 7,
      '4': 1,
      '5': 4,
      '10': 'overflowRejectedCount'
    },
    {
      '1': 'oversize_rejected_count',
      '3': 8,
      '4': 1,
      '5': 4,
      '10': 'oversizeRejectedCount'
    },
    {
      '1': 'previous_boot_discarded_count',
      '3': 9,
      '4': 1,
      '5': 4,
      '10': 'previousBootDiscardedCount'
    },
    {
      '1': 'storage_available',
      '3': 10,
      '4': 1,
      '5': 8,
      '10': 'storageAvailable'
    },
  ],
};

/// Descriptor for `HighRiskDeliveryStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List highRiskDeliveryStatusDescriptor = $convert.base64Decode(
    'ChZIaWdoUmlza0RlbGl2ZXJ5U3RhdHVzEiMKDXBlbmRpbmdfY291bnQYASABKA1SDHBlbmRpbm'
    'dDb3VudBIjCg1wZW5kaW5nX2J5dGVzGAIgASgEUgxwZW5kaW5nQnl0ZXMSHwoLYWNrZWRfY291'
    'bnQYAyABKARSCmFja2VkQ291bnQSIwoNZXhwaXJlZF9jb3VudBgEIAEoBFIMZXhwaXJlZENvdW'
    '50EjQKFm92ZXJmbG93X2V2aWN0ZWRfY291bnQYBSABKARSFG92ZXJmbG93RXZpY3RlZENvdW50'
    'Ei4KE3N0b3JhZ2VfZXJyb3JfY291bnQYBiABKARSEXN0b3JhZ2VFcnJvckNvdW50EjYKF292ZX'
    'JmbG93X3JlamVjdGVkX2NvdW50GAcgASgEUhVvdmVyZmxvd1JlamVjdGVkQ291bnQSNgoXb3Zl'
    'cnNpemVfcmVqZWN0ZWRfY291bnQYCCABKARSFW92ZXJzaXplUmVqZWN0ZWRDb3VudBJBCh1wcm'
    'V2aW91c19ib290X2Rpc2NhcmRlZF9jb3VudBgJIAEoBFIacHJldmlvdXNCb290RGlzY2FyZGVk'
    'Q291bnQSKwoRc3RvcmFnZV9hdmFpbGFibGUYCiABKAhSEHN0b3JhZ2VBdmFpbGFibGU=');

@$core.Deprecated('Use resourcePressureStatusDescriptor instead')
const ResourcePressureStatus$json = {
  '1': 'ResourcePressureStatus',
  '2': [
    {
      '1': 'level',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.ResourceLevel',
      '10': 'level'
    },
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `ResourcePressureStatus`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resourcePressureStatusDescriptor =
    $convert.base64Decode(
        'ChZSZXNvdXJjZVByZXNzdXJlU3RhdHVzEjEKBWxldmVsGAEgASgOMhsucG9ja2V0bmV0LnYxLl'
        'Jlc291cmNlTGV2ZWxSBWxldmVsEhYKBnJlYXNvbhgCIAEoCVIGcmVhc29u');

@$core.Deprecated('Use componentHealthDescriptor instead')
const ComponentHealth$json = {
  '1': 'ComponentHealth',
  '2': [
    {
      '1': 'component_id',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.ComponentId',
      '10': 'componentId'
    },
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.ComponentState',
      '10': 'state'
    },
    {'1': 'reason', '3': 3, '4': 1, '5': 9, '10': 'reason'},
    {'1': 'last_ok_ms', '3': 4, '4': 1, '5': 3, '10': 'lastOkMs'},
    {'1': 'sampled_at_ms', '3': 5, '4': 1, '5': 3, '10': 'sampledAtMs'},
    {'1': 'recovery_phase', '3': 6, '4': 1, '5': 9, '10': 'recoveryPhase'},
  ],
};

/// Descriptor for `ComponentHealth`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List componentHealthDescriptor = $convert.base64Decode(
    'Cg9Db21wb25lbnRIZWFsdGgSPAoMY29tcG9uZW50X2lkGAEgASgOMhkucG9ja2V0bmV0LnYxLk'
    'NvbXBvbmVudElkUgtjb21wb25lbnRJZBIyCgVzdGF0ZRgCIAEoDjIcLnBvY2tldG5ldC52MS5D'
    'b21wb25lbnRTdGF0ZVIFc3RhdGUSFgoGcmVhc29uGAMgASgJUgZyZWFzb24SHAoKbGFzdF9va1'
    '9tcxgEIAEoA1IIbGFzdE9rTXMSIgoNc2FtcGxlZF9hdF9tcxgFIAEoA1ILc2FtcGxlZEF0TXMS'
    'JQoOcmVjb3ZlcnlfcGhhc2UYBiABKAlSDXJlY292ZXJ5UGhhc2U=');

@$core.Deprecated('Use deviceHealthDescriptor instead')
const DeviceHealth$json = {
  '1': 'DeviceHealth',
  '2': [
    {
      '1': 'components',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.pocketnet.v1.ComponentHealth',
      '10': 'components'
    },
  ],
};

/// Descriptor for `DeviceHealth`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceHealthDescriptor = $convert.base64Decode(
    'CgxEZXZpY2VIZWFsdGgSPQoKY29tcG9uZW50cxgBIAMoCzIdLnBvY2tldG5ldC52MS5Db21wb2'
    '5lbnRIZWFsdGhSCmNvbXBvbmVudHM=');

@$core.Deprecated('Use observedTrafficDescriptor instead')
const ObservedTraffic$json = {
  '1': 'ObservedTraffic',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.TrafficStatus',
      '10': 'status'
    },
    {'1': 'observed_bytes', '3': 2, '4': 1, '5': 4, '10': 'observedBytes'},
    {'1': 'window_ms', '3': 3, '4': 1, '5': 13, '10': 'windowMs'},
    {'1': 'estimated', '3': 4, '4': 1, '5': 8, '10': 'estimated'},
  ],
};

/// Descriptor for `ObservedTraffic`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List observedTrafficDescriptor = $convert.base64Decode(
    'Cg9PYnNlcnZlZFRyYWZmaWMSMwoGc3RhdHVzGAEgASgOMhsucG9ja2V0bmV0LnYxLlRyYWZmaW'
    'NTdGF0dXNSBnN0YXR1cxIlCg5vYnNlcnZlZF9ieXRlcxgCIAEoBFINb2JzZXJ2ZWRCeXRlcxIb'
    'Cgl3aW5kb3dfbXMYAyABKA1SCHdpbmRvd01zEhwKCWVzdGltYXRlZBgEIAEoCFIJZXN0aW1hdG'
    'Vk');

@$core.Deprecated('Use ssidTrafficDescriptor instead')
const SsidTraffic$json = {
  '1': 'SsidTraffic',
  '2': [
    {'1': 'ssid', '3': 1, '4': 1, '5': 9, '10': 'ssid'},
    {
      '1': 'traffic',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.ObservedTraffic',
      '10': 'traffic'
    },
  ],
};

/// Descriptor for `SsidTraffic`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List ssidTrafficDescriptor = $convert.base64Decode(
    'CgtTc2lkVHJhZmZpYxISCgRzc2lkGAEgASgJUgRzc2lkEjcKB3RyYWZmaWMYAiABKAsyHS5wb2'
    'NrZXRuZXQudjEuT2JzZXJ2ZWRUcmFmZmljUgd0cmFmZmlj');

@$core.Deprecated('Use observedDeviceDescriptor instead')
const ObservedDevice$json = {
  '1': 'ObservedDevice',
  '2': [
    {'1': 'device_key', '3': 1, '4': 1, '5': 9, '10': 'deviceKey'},
    {'1': 'mac', '3': 2, '4': 1, '5': 9, '10': 'mac'},
    {
      '1': 'kind',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.ObservedDeviceKind',
      '10': 'kind'
    },
    {'1': 'ssid', '3': 4, '4': 1, '5': 9, '10': 'ssid'},
    {'1': 'bssid', '3': 5, '4': 1, '5': 9, '10': 'bssid'},
    {'1': 'channel', '3': 6, '4': 1, '5': 9, '10': 'channel'},
    {'1': 'rssi_dbm', '3': 7, '4': 1, '5': 2, '10': 'rssiDbm'},
    {'1': 'first_seen_ms', '3': 8, '4': 1, '5': 3, '10': 'firstSeenMs'},
    {'1': 'last_seen_ms', '3': 9, '4': 1, '5': 3, '10': 'lastSeenMs'},
    {
      '1': 'association_state',
      '3': 10,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.AssociationState',
      '10': 'associationState'
    },
    {'1': 'related_ap_bssid', '3': 11, '4': 1, '5': 9, '10': 'relatedApBssid'},
    {'1': 'source_scope', '3': 12, '4': 1, '5': 9, '10': 'sourceScope'},
    {'1': 'security', '3': 13, '4': 1, '5': 9, '10': 'security'},
    {
      '1': 'traffic',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.pocketnet.v1.ObservedTraffic',
      '10': 'traffic'
    },
  ],
};

/// Descriptor for `ObservedDevice`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List observedDeviceDescriptor = $convert.base64Decode(
    'Cg5PYnNlcnZlZERldmljZRIdCgpkZXZpY2Vfa2V5GAEgASgJUglkZXZpY2VLZXkSEAoDbWFjGA'
    'IgASgJUgNtYWMSNAoEa2luZBgDIAEoDjIgLnBvY2tldG5ldC52MS5PYnNlcnZlZERldmljZUtp'
    'bmRSBGtpbmQSEgoEc3NpZBgEIAEoCVIEc3NpZBIUCgVic3NpZBgFIAEoCVIFYnNzaWQSGAoHY2'
    'hhbm5lbBgGIAEoCVIHY2hhbm5lbBIZCghyc3NpX2RibRgHIAEoAlIHcnNzaURibRIiCg1maXJz'
    'dF9zZWVuX21zGAggASgDUgtmaXJzdFNlZW5NcxIgCgxsYXN0X3NlZW5fbXMYCSABKANSCmxhc3'
    'RTZWVuTXMSSwoRYXNzb2NpYXRpb25fc3RhdGUYCiABKA4yHi5wb2NrZXRuZXQudjEuQXNzb2Np'
    'YXRpb25TdGF0ZVIQYXNzb2NpYXRpb25TdGF0ZRIoChByZWxhdGVkX2FwX2Jzc2lkGAsgASgJUg'
    '5yZWxhdGVkQXBCc3NpZBIhCgxzb3VyY2Vfc2NvcGUYDCABKAlSC3NvdXJjZVNjb3BlEhoKCHNl'
    'Y3VyaXR5GA0gASgJUghzZWN1cml0eRI3Cgd0cmFmZmljGA4gASgLMh0ucG9ja2V0bmV0LnYxLk'
    '9ic2VydmVkVHJhZmZpY1IHdHJhZmZpYw==');

@$core.Deprecated('Use observedDevicesRequestDescriptor instead')
const ObservedDevicesRequest$json = {
  '1': 'ObservedDevicesRequest',
  '2': [
    {'1': 'phone_id', '3': 1, '4': 1, '5': 9, '10': 'phoneId'},
    {'1': 'page_token', '3': 2, '4': 1, '5': 9, '10': 'pageToken'},
    {'1': 'page_size', '3': 3, '4': 1, '5': 13, '10': 'pageSize'},
    {'1': 'ssid_filter', '3': 4, '4': 1, '5': 9, '10': 'ssidFilter'},
    {'1': 'bssid_filter', '3': 5, '4': 1, '5': 9, '10': 'bssidFilter'},
    {
      '1': 'kind',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.ObservedDeviceKind',
      '10': 'kind'
    },
  ],
};

/// Descriptor for `ObservedDevicesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List observedDevicesRequestDescriptor = $convert.base64Decode(
    'ChZPYnNlcnZlZERldmljZXNSZXF1ZXN0EhkKCHBob25lX2lkGAEgASgJUgdwaG9uZUlkEh0KCn'
    'BhZ2VfdG9rZW4YAiABKAlSCXBhZ2VUb2tlbhIbCglwYWdlX3NpemUYAyABKA1SCHBhZ2VTaXpl'
    'Eh8KC3NzaWRfZmlsdGVyGAQgASgJUgpzc2lkRmlsdGVyEiEKDGJzc2lkX2ZpbHRlchgFIAEoCV'
    'ILYnNzaWRGaWx0ZXISNAoEa2luZBgGIAEoDjIgLnBvY2tldG5ldC52MS5PYnNlcnZlZERldmlj'
    'ZUtpbmRSBGtpbmQ=');

@$core.Deprecated('Use observedDevicesPageDescriptor instead')
const ObservedDevicesPage$json = {
  '1': 'ObservedDevicesPage',
  '2': [
    {
      '1': 'devices',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.pocketnet.v1.ObservedDevice',
      '10': 'devices'
    },
    {'1': 'next_page_token', '3': 2, '4': 1, '5': 9, '10': 'nextPageToken'},
    {'1': 'generation', '3': 3, '4': 1, '5': 4, '10': 'generation'},
    {'1': 'truncated', '3': 4, '4': 1, '5': 8, '10': 'truncated'},
    {'1': 'sampled_at_ms', '3': 5, '4': 1, '5': 3, '10': 'sampledAtMs'},
    {'1': 'coverage', '3': 6, '4': 1, '5': 9, '10': 'coverage'},
    {'1': 'total_count', '3': 7, '4': 1, '5': 13, '10': 'totalCount'},
    {
      '1': 'ssid_traffic',
      '3': 8,
      '4': 3,
      '5': 11,
      '6': '.pocketnet.v1.SsidTraffic',
      '10': 'ssidTraffic'
    },
  ],
};

/// Descriptor for `ObservedDevicesPage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List observedDevicesPageDescriptor = $convert.base64Decode(
    'ChNPYnNlcnZlZERldmljZXNQYWdlEjYKB2RldmljZXMYASADKAsyHC5wb2NrZXRuZXQudjEuT2'
    'JzZXJ2ZWREZXZpY2VSB2RldmljZXMSJgoPbmV4dF9wYWdlX3Rva2VuGAIgASgJUg1uZXh0UGFn'
    'ZVRva2VuEh4KCmdlbmVyYXRpb24YAyABKARSCmdlbmVyYXRpb24SHAoJdHJ1bmNhdGVkGAQgAS'
    'gIUgl0cnVuY2F0ZWQSIgoNc2FtcGxlZF9hdF9tcxgFIAEoA1ILc2FtcGxlZEF0TXMSGgoIY292'
    'ZXJhZ2UYBiABKAlSCGNvdmVyYWdlEh8KC3RvdGFsX2NvdW50GAcgASgNUgp0b3RhbENvdW50Ej'
    'wKDHNzaWRfdHJhZmZpYxgIIAMoCzIZLnBvY2tldG5ldC52MS5Tc2lkVHJhZmZpY1ILc3NpZFRy'
    'YWZmaWM=');

@$core.Deprecated('Use setCaptureProfileRequestDescriptor instead')
const SetCaptureProfileRequest$json = {
  '1': 'SetCaptureProfileRequest',
  '2': [
    {'1': 'phone_id', '3': 1, '4': 1, '5': 9, '10': 'phoneId'},
    {'1': 'request_id', '3': 2, '4': 1, '5': 9, '10': 'requestId'},
    {
      '1': 'target_profile',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.CaptureProfile',
      '10': 'targetProfile'
    },
  ],
};

/// Descriptor for `SetCaptureProfileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setCaptureProfileRequestDescriptor = $convert.base64Decode(
    'ChhTZXRDYXB0dXJlUHJvZmlsZVJlcXVlc3QSGQoIcGhvbmVfaWQYASABKAlSB3Bob25lSWQSHQ'
    'oKcmVxdWVzdF9pZBgCIAEoCVIJcmVxdWVzdElkEkMKDnRhcmdldF9wcm9maWxlGAMgASgOMhwu'
    'cG9ja2V0bmV0LnYxLkNhcHR1cmVQcm9maWxlUg10YXJnZXRQcm9maWxl');

@$core.Deprecated('Use recoverComponentRequestDescriptor instead')
const RecoverComponentRequest$json = {
  '1': 'RecoverComponentRequest',
  '2': [
    {'1': 'phone_id', '3': 1, '4': 1, '5': 9, '10': 'phoneId'},
    {'1': 'request_id', '3': 2, '4': 1, '5': 9, '10': 'requestId'},
    {
      '1': 'component',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.ComponentId',
      '10': 'component'
    },
    {
      '1': 'allow_hotspot_restart',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'allowHotspotRestart'
    },
  ],
};

/// Descriptor for `RecoverComponentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List recoverComponentRequestDescriptor = $convert.base64Decode(
    'ChdSZWNvdmVyQ29tcG9uZW50UmVxdWVzdBIZCghwaG9uZV9pZBgBIAEoCVIHcGhvbmVJZBIdCg'
    'pyZXF1ZXN0X2lkGAIgASgJUglyZXF1ZXN0SWQSNwoJY29tcG9uZW50GAMgASgOMhkucG9ja2V0'
    'bmV0LnYxLkNvbXBvbmVudElkUgljb21wb25lbnQSMgoVYWxsb3dfaG90c3BvdF9yZXN0YXJ0GA'
    'QgASgIUhNhbGxvd0hvdHNwb3RSZXN0YXJ0');

@$core.Deprecated('Use controlCommandResponseDescriptor instead')
const ControlCommandResponse$json = {
  '1': 'ControlCommandResponse',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'accepted', '3': 2, '4': 1, '5': 8, '10': 'accepted'},
    {
      '1': 'status',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.pocketnet.v1.CommandStatus',
      '10': 'status'
    },
    {'1': 'reason', '3': 4, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `ControlCommandResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlCommandResponseDescriptor = $convert.base64Decode(
    'ChZDb250cm9sQ29tbWFuZFJlc3BvbnNlEh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcXVlc3RJZB'
    'IaCghhY2NlcHRlZBgCIAEoCFIIYWNjZXB0ZWQSMwoGc3RhdHVzGAMgASgOMhsucG9ja2V0bmV0'
    'LnYxLkNvbW1hbmRTdGF0dXNSBnN0YXR1cxIWCgZyZWFzb24YBCABKAlSBnJlYXNvbg==');
