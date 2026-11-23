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
  ],
};

/// Descriptor for `SubscribeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List subscribeRequestDescriptor = $convert.base64Decode(
    'ChBTdWJzY3JpYmVSZXF1ZXN0EhsKCWRldmljZV9pZBgBIAEoCVIIZGV2aWNlSWQSLgoTbGFzdF'
    '9ldmVudF9zZXF1ZW5jZRgCIAEoBFIRbGFzdEV2ZW50U2VxdWVuY2USIAoMbGFzdF9ib290X2lk'
    'GAMgASgJUgpsYXN0Qm9vdElk');

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
    'RuZXQudjEuSGlzdG9yeUdhcEgAUgpoaXN0b3J5R2FwQgkKB3BheWxvYWQ=');

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
    'BvY2tldG5ldC52MS5EZWxpdmVyeU1ldHJpY3NSCGRlbGl2ZXJ5');

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
    'EiAKC29jY3VycmVuY2VzGAsgASgNUgtvY2N1cnJlbmNlcw==');

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
