import 'package:json_schema/json_schema.dart';

import '../network.dart';

enum CapabilityStatus { available, unavailable, degraded, error, unknown }

CapabilityStatus _status(Object? value) => switch (value) {
  'AVAILABLE' => CapabilityStatus.available,
  'UNAVAILABLE' => CapabilityStatus.unavailable,
  'DEGRADED' => CapabilityStatus.degraded,
  'ERROR' => CapabilityStatus.error,
  _ => CapabilityStatus.unknown,
};

class KismetStatus {
  KismetStatus.fromJson(Json data)
    : installed = data['installed'] is bool ? data['installed'] as bool : null,
      running = data['running'] is bool ? data['running'] as bool : null,
      version = data['version'] is String ? data['version'] as String : null,
      datasourceCount = switch (data['datasource_count']) {
        final int count when count >= 0 => count,
        _ => null,
      },
      wirelessStatus = _status(data['wireless_status']),
      reason = data['reason'] is String ? data['reason'] as String : null,
      sources = _sourceStates(data['source_states']);

  static Map<String, ({CapabilityStatus status, String? reason})> _sourceStates(
    Object? raw,
  ) {
    if (raw is! Json) return const {};
    return Map.unmodifiable({
      for (final entry in raw.entries)
        if (entry.value case final Json details)
          entry.key: (
            status: _status(details['status']),
            reason: details['reason'] is String
                ? (details['reason'] as String).trim()
                : null,
          ),
    });
  }

  final bool? installed;
  final bool? running;
  final String? version;
  final int? datasourceCount;
  final CapabilityStatus wirelessStatus;
  final String? reason;
  final Map<String, ({CapabilityStatus status, String? reason})> sources;
}

class DeviceTool {
  const DeviceTool._(
    this.name,
    this.description,
    this.inputSchema,
    this.status,
    this.domain,
    this.reason,
    this._readOnly,
    this._validator,
  );

  final String name;
  final String description;
  final Json inputSchema;
  final CapabilityStatus status;
  final String domain;
  final String? reason;
  final bool _readOnly;
  final JsonSchema _validator;

  bool get isCallable => status == CapabilityStatus.available && _readOnly;
}

class ToolRegistry {
  ToolRegistry._(Map<String, DeviceTool> tools, this.kismet)
    : _tools = Map.unmodifiable(tools);

  factory ToolRegistry.fromTools(
    List<Json> entries, {
    List<Json>? capabilities,
    KismetStatus? kismet,
  }) {
    final tools = <String, DeviceTool>{};
    final reported = capabilities == null ? null : _parseStatuses(capabilities);
    for (final entry in entries) {
      final name = entry['name'];
      final description = entry['description'];
      final schema = entry['inputSchema'];
      final annotations = entry['annotations'];
      if (name is! String ||
          !_toolName.hasMatch(name) ||
          description is! String ||
          description.trim().isEmpty ||
          schema is! Json ||
          schema['type'] != 'object' ||
          (annotations != null && annotations is! Json)) {
        throw const FormatException('树莓派返回了无效的工具定义');
      }
      if (tools.containsKey(name)) {
        throw FormatException('树莓派返回了重复的工具（$name）');
      }
      final capability = reported?.remove(name);
      if (reported != null && capability == null) {
        throw FormatException('树莓派未报告工具状态（$name）');
      }

      final JsonSchema validator;
      try {
        validator = JsonSchema.create(
          schema,
          schemaVersion: schema.containsKey(r'$schema')
              ? null
              : SchemaVersion.draft2020_12,
        );
      } catch (_) {
        throw FormatException('树莓派返回了无效的参数 Schema（$name）');
      }
      tools[name] = DeviceTool._(
        name,
        description.trim(),
        _freeze(schema) as Json,
        capability?.status ?? CapabilityStatus.unknown,
        capability?.domain ?? 'other',
        capability?.reason,
        annotations is Json &&
            annotations['readOnlyHint'] == true &&
            annotations['destructiveHint'] != true &&
            !_legacyDevelopmentTools.contains(name.toLowerCase()) &&
            !_commandTool.hasMatch(name),
        validator,
      );
    }
    if (reported?.isNotEmpty ?? false) {
      throw const FormatException('树莓派报告了未注册工具的状态');
    }
    return ToolRegistry._(tools, kismet);
  }

  static Map<String, ({CapabilityStatus status, String domain, String? reason})>
  _parseStatuses(List<Json> entries) {
    final reported =
        <String, ({CapabilityStatus status, String domain, String? reason})>{};
    for (final entry in entries) {
      final name = entry['name'];
      final domain = entry['domain'];
      final status = _status(entry['status']);
      if (name is! String ||
          !_toolName.hasMatch(name) ||
          status == CapabilityStatus.unknown ||
          (domain != null && (domain is! String || domain.trim().isEmpty))) {
        throw const FormatException('树莓派返回了无效的工具状态');
      }
      if (reported.containsKey(name)) {
        throw FormatException('树莓派重复报告了工具状态（$name）');
      }
      final reason = entry['reason'];
      reported[name] = (
        status: status,
        domain: domain as String? ?? 'other',
        reason: reason is String && reason.trim().isNotEmpty
            ? reason.trim()
            : null,
      );
    }
    return reported;
  }

  static final _toolName = RegExp(r'^[A-Za-z0-9_.-]{1,128}$');
  static final _commandTool = RegExp(
    r'(^|[_.-])(shell|command|cmd|exec|execute|git)([_.-]|$)',
    caseSensitive: false,
  );
  static const _legacyDevelopmentTools = {
    'list_files',
    'read_file',
    'create_directory',
    'create_project',
    'write_file',
    'compile_project',
    'run_tests',
  };

  final Map<String, DeviceTool> _tools;
  final KismetStatus? kismet;

  List<DeviceTool> get tools => List.unmodifiable(_tools.values);
  List<DeviceTool> get callableTools =>
      List.unmodifiable(_tools.values.where((tool) => tool.isCallable));

  DeviceTool? operator [](String name) => _tools[name];

  void validateArguments(String name, Json arguments) {
    final tool = this[name];
    if (tool == null) {
      throw FormatException('当前设备未提供此工具（$name）');
    }
    if (!tool.isCallable) {
      throw FormatException('当前工具不可调用（$name）');
    }
    if (!tool._validator.validate(arguments).isValid) {
      throw FormatException('参数不符合工具声明的 Schema（$name）');
    }
  }

  static Object? _freeze(Object? value) => switch (value) {
    final Json map => Json.unmodifiable({
      for (final entry in map.entries) entry.key: _freeze(entry.value),
    }),
    final List<dynamic> list => List.unmodifiable(list.map(_freeze)),
    _ => value,
  };
}
