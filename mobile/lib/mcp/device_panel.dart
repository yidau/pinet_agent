import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';
import 'device_connection.dart';
import 'tool_registry.dart';

String capabilityStatusLabel(CapabilityStatus status) => switch (status) {
  CapabilityStatus.available => '可用',
  CapabilityStatus.unavailable => '未实现',
  CapabilityStatus.degraded => '条件不足',
  CapabilityStatus.error => '运行错误',
  CapabilityStatus.unknown => '未报告',
};

class DevicePanel extends StatelessWidget {
  const DevicePanel({
    super.key,
    required this.connection,
    required this.endpoint,
    required this.configuredName,
    required this.onConnect,
    this.statusPrefix = '',
  });

  final DeviceConnection connection;
  final Uri? endpoint;
  final String? configuredName;
  final VoidCallback? onConnect;
  final String statusPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = connection.status;
    final statusLabel = switch (status) {
      DeviceConnectionStatus.disconnected => '未连接',
      DeviceConnectionStatus.connecting => '正在连接',
      DeviceConnectionStatus.discovering => '正在获取能力',
      DeviceConnectionStatus.ready => '已连接',
      DeviceConnectionStatus.error => '连接失败',
    };
    final statusColor = switch (status) {
      DeviceConnectionStatus.ready => ConsoleColors.successOf(context),
      DeviceConnectionStatus.error => colors.error,
      DeviceConnectionStatus.connecting ||
      DeviceConnectionStatus.discovering => colors.primary,
      DeviceConnectionStatus.disconnected => colors.onSurfaceVariant,
    };
    final session = connection.session;
    final name = connection.deviceName ?? configuredName ?? '树莓派';
    final pending =
        status == DeviceConnectionStatus.connecting ||
        status == DeviceConnectionStatus.discovering;
    final stateIcon = switch (status) {
      DeviceConnectionStatus.ready => Icons.check_circle_outline,
      DeviceConnectionStatus.error => Icons.error_outline,
      DeviceConnectionStatus.connecting ||
      DeviceConnectionStatus.discovering => Icons.sync,
      _ => Icons.link_off,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant, width: 0.65),
            borderRadius: BorderRadius.circular(14),
          ),
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(stateIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: [name, ?endpoint?.toString()].join('\n'),
                  child: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                      Text(
                        '$statusPrefix$statusLabel',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (session != null)
                TextButton(
                  onPressed: () => _showCapabilities(context, session),
                  child: Text('设备能力（${session.registry.tools.length}）'),
                )
              else if (pending)
                TextButton(
                  onPressed: () => unawaited(connection.disconnect()),
                  child: const Text('取消'),
                )
              else
                TextButton(onPressed: onConnect, child: const Text('连接设备')),
            ],
          ),
        ),
        if (connection.error case final String reason)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
            child: Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }

  Future<void> _showCapabilities(
    BuildContext context,
    DeviceSession session,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: ListenableBuilder(
            listenable: connection,
            builder: (context, _) {
              if (!identical(connection.session, session)) {
                return const Center(child: Text('设备连接已断开。'));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '设备能力',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (session.registry.kismet != null)
                          IconButton(
                            tooltip: '刷新设备能力',
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              try {
                                await session.refreshCapabilities();
                              } on FormatException {
                                // The connection state reports the failure.
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _Capabilities(registry: session.registry)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

const sourceLabels = {
  'managed_scan': 'Wi-Fi Managed Scan',
  'monitor_mode': 'Wi-Fi Monitor Mode',
  'bluetooth_scan': 'Bluetooth Active Scan',
  'pcap_replay': 'PCAP Replay',
};

const _domains = <String, (String, IconData)>{
  'device': ('设备信息', Icons.memory_outlined),
  'kismet': ('Kismet', Icons.sensors),
  'bluetooth': ('蓝牙发现', Icons.bluetooth_outlined),
  'wireless_discovery': ('无线发现', Icons.wifi_find),
  'wireless_monitoring': ('无线监测', Icons.monitor_heart_outlined),
  'network_discovery': ('网络发现', Icons.hub_outlined),
  'packet_analysis': ('报文分析', Icons.layers_outlined),
  'security_analysis': ('安全分析', Icons.shield_outlined),
  'network_diagnosis': ('网络诊断', Icons.fact_check_outlined),
};

class _Capabilities extends StatelessWidget {
  const _Capabilities({required this.registry});

  final ToolRegistry registry;

  @override
  Widget build(BuildContext context) {
    final tools = registry.tools;
    if (tools.isEmpty) {
      return const Center(child: Text('设备没有注册 MCP 工具。'));
    }
    final groups = <String, List<DeviceTool>>{};
    for (final tool in tools) {
      final domain = _domains.containsKey(tool.domain) ? tool.domain : 'other';
      groups.putIfAbsent(domain, () => []).add(tool);
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (registry.kismet case final kismet?) ...[
          Text('Kismet 观测引擎', style: theme.textTheme.titleMedium),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(switch (kismet.installed) {
                  true => '已安装',
                  false => '未安装',
                  null => '安装状态未知',
                }),
                Text(switch (kismet.running) {
                  true => '运行中',
                  false => '未运行',
                  null => '运行状态未知',
                }),
                Text('版本 ${kismet.version ?? '未知'}'),
                Text('数据源 ${kismet.datasourceCount ?? '未知'}'),
                Text('无线观测 · ${capabilityStatusLabel(kismet.wirelessStatus)}'),
              ],
            ),
          ),
          if (kismet.reason case final reason? when reason.isNotEmpty)
            Text(reason, style: theme.textTheme.bodySmall),
          if (kismet.sources.isNotEmpty)
            for (final entry in sourceLabels.entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.value} · ${capabilityStatusLabel(kismet.sources[entry.key]?.status ?? CapabilityStatus.unknown)}',
                    ),
                    if (kismet.sources[entry.key]?.reason case final reason?
                        when reason.isNotEmpty)
                      Text(reason, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
          const Divider(),
        ],
        for (final domain in [..._domains.keys, 'other'])
          if (groups[domain] case final entries?) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Row(
                children: [
                  Icon(
                    _domains[domain]?.$2 ?? Icons.more_horiz,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _domains[domain]?.$1 ?? '其他能力',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            for (final tool in entries) _CapabilityRow(tool: tool),
          ],
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.tool});

  final DeviceTool tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = switch (tool.status) {
      CapabilityStatus.available => ConsoleColors.successOf(context),
      CapabilityStatus.error => colors.error,
      CapabilityStatus.degraded => ConsoleColors.warningOf(context),
      CapabilityStatus.unavailable ||
      CapabilityStatus.unknown => colors.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.name, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  tool.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (tool.reason case final reason?)
                  Text(reason, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                capabilityStatusLabel(tool.status),
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
