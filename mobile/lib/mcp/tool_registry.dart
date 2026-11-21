import 'package:json_schema/json_schema.dart';

import '../network.dart';

class DeviceTool {
  const DeviceTool._(
    this.name,
    this.description,
    this.inputSchema,
    this._validator,
  );

  final String name;
  final String description;
  final Json inputSchema;
  final JsonSchema _validator;
}

class ToolRegistry {
  ToolRegistry._(Map<String, DeviceTool> tools)
    : _tools = Map.unmodifiable(tools);

  factory ToolRegistry.fromTools(List<Json> entries) {
    final tools = <String, DeviceTool>{};
    final seen = <String>{};
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
      if (!seen.add(name)) {
        throw FormatException('树莓派返回了重复的工具（$name）');
      }

      // The existing server also serves older clients. Only declared read-only
      // observations are made available to this version of the Agent.
      if (annotations is! Json ||
          annotations['readOnlyHint'] != true ||
          _legacyDevelopmentTools.contains(name.toLowerCase()) ||
          _commandTool.hasMatch(name)) {
        continue;
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
        validator,
      );
    }
    return ToolRegistry._(tools);
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

  List<DeviceTool> get tools => List.unmodifiable(_tools.values);

  DeviceTool? operator [](String name) => _tools[name];

  void validateArguments(String name, Json arguments) {
    final tool = this[name];
    if (tool == null) {
      throw FormatException('当前设备未提供此工具（$name）');
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
