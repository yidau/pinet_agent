import '../mcp/device_connection.dart';
import '../mcp/tool_registry.dart';
import '../network.dart';

/// Presentation of the currently connected device's last successful replies.
class WorkspaceData {
  const WorkspaceData(this.session, this.observations);

  final DeviceSession? session;
  final Map<String, Json> observations;

  Json? result(String tool) {
    if (session?.registry[tool]?.status != CapabilityStatus.available) {
      return null;
    }
    final reply = observations[tool];
    if (reply == null || reply['ok'] == false) return null;
    return reply['data'] is Json ? reply['data'] as Json : reply;
  }

  List<Json>? rows(String tool, String field) {
    final value = result(tool)?[field];
    if (value is! List || value.any((row) => row is! Json)) return null;
    return value.cast<Json>();
  }

  String? count(String tool, String field) {
    final reply = result(tool);
    final total = reply?['total'] ?? reply?['count'];
    if (total is int && total >= 0) return total.toString();
    final length = rows(tool, field)?.length;
    if (length == null) return null;
    return reply?['truncated'] == true ? '≥$length' : '$length';
  }

  String reason(String name) {
    if (session == null) return '连接树莓派后可读取。';
    final tool = session?.registry[name];
    if (tool == null) return '当前设备未提供此能力。';
    final reply = observations[name];
    if (reply?['ok'] == false) {
      return displayText(reply?['message']) ?? '本次读取失败。';
    }
    final reason = displayText(tool.reason);
    if (reason != null && reason != 'This capability is not implemented.') {
      return reason;
    }
    return switch (tool.status) {
      CapabilityStatus.available => reply == null ? '等待读取设备数据。' : '设备未报告此数据。',
      CapabilityStatus.unavailable => '当前设备尚未实现此能力。',
      CapabilityStatus.degraded => '当前数据源不满足观测条件。',
      CapabilityStatus.error => '设备报告此能力运行出错。',
      CapabilityStatus.unknown => '设备未报告可用状态。',
    };
  }
}

String? displayText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

String sourceName(Object? value) => switch (value) {
  'managed_scan' || 'Managed Scan' => '普通 Wi-Fi 扫描',
  'monitor_mode' => 'Wi-Fi 监听',
  'bluetooth_scan' => '蓝牙发现',
  'pcap_replay' => '离线文件重放',
  'local capture directory' => '树莓派文件库',
  'local replay controller' => '本地重放服务',
  'platform.uname+os-release' || 'platform.uname' => '树莓派系统',
  'psutil' => '树莓派系统监测',
  'kismet' => 'Kismet',
  'managed_scan+kismet' => '普通扫描与 Kismet 监听',
  _ => displayText(value) ?? '来源未报告',
};

DateTime? deviceTime(Object? raw) {
  if (raw is num && raw.isFinite && raw >= 0 && raw < 8640000000000) {
    return DateTime.fromMillisecondsSinceEpoch(
      (raw * 1000).round(),
      isUtc: true,
    ).toLocal();
  }
  if (raw is String) return DateTime.tryParse(raw)?.toLocal();
  return null;
}

String displayTime(DateTime time) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} ${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}

String evidenceLine(Json reply) {
  final time = deviceTime(reply['timestamp']);
  return [
    sourceName(reply['source']),
    time == null ? '读取时间未报告' : '读取于 ${displayTime(time)}',
  ].join(' · ');
}

String? displayBytes(Object? value) {
  if (value is! int || value < 0) return null;
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KiB';
  return '$value B';
}
