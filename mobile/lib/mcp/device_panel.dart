import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'device_connection.dart';
import 'tool_registry.dart';

class DevicePanel extends StatelessWidget {
  const DevicePanel({
    super.key,
    required this.connection,
    required this.endpoint,
    required this.configuredName,
    required this.onConnect,
  });

  final DeviceConnection connection;
  final Uri? endpoint;
  final String? configuredName;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = connection.status;
    final statusLabel = switch (status) {
      DeviceConnectionStatus.disconnected => '未连接',
      DeviceConnectionStatus.connecting => '正在连接',
      DeviceConnectionStatus.discovering => '正在获取能力',
      DeviceConnectionStatus.ready => '已连接',
      DeviceConnectionStatus.error => '连接失败',
    };
    final canDisconnect =
        status == DeviceConnectionStatus.connecting ||
        status == DeviceConnectionStatus.discovering ||
        status == DeviceConnectionStatus.ready;
    final session = connection.session;

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        configuredName ?? connection.deviceName ?? '树莓派',
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        endpoint?.toString() ?? '未配置设备地址',
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        statusLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: switch (status) {
                            DeviceConnectionStatus.error =>
                              theme.colorScheme.error,
                            DeviceConnectionStatus.ready =>
                              theme.colorScheme.primary,
                            _ => theme.colorScheme.onSurfaceVariant,
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (canDisconnect)
                  OutlinedButton(
                    onPressed: () => unawaited(connection.disconnect()),
                    child: const Text('断开连接'),
                  )
                else
                  FilledButton(onPressed: onConnect, child: const Text('连接设备')),
              ],
            ),
          ),
          if (connection.error case final reason?)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                reason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          if (session != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showCapabilities(context, session),
                icon: const Icon(Icons.list_alt),
                label: Text('设备能力（${session.registry.tools.length}）'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showCapabilities(
    BuildContext context,
    DeviceSession session,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: connection,
          builder: (context, _) {
            if (!identical(connection.session, session)) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('设备连接已断开。'),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Text(
                    '设备能力',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _Capabilities(tools: session.registry.tools),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _CapabilityGroup {
  device('设备信息'),
  network('网络信息'),
  other('其他能力');

  const _CapabilityGroup(this.label);

  final String label;

  static _CapabilityGroup forTool(DeviceTool tool) {
    final text = '${tool.name.replaceAll('_', ' ')} ${tool.description}'
        .toLowerCase();
    const networkTerms = [
      'network',
      'wi-fi',
      'wifi',
      'wireless',
      'access point',
      'ip address',
      '网络',
      '网卡',
      '无线',
      '接入点',
      '信道',
      '路由',
    ];
    const deviceTerms = [
      'system',
      'device',
      'cpu',
      'memory',
      'disk',
      'temperature',
      '系统',
      '设备',
      '内存',
      '磁盘',
      '温度',
    ];
    if (networkTerms.any((term) => text.contains(term))) return network;
    if (deviceTerms.any((term) => text.contains(term))) return device;
    return other;
  }
}

class _Capabilities extends StatelessWidget {
  const _Capabilities({required this.tools});

  final List<DeviceTool> tools;

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Text('设备没有提供可用的只读工具。'),
      );
    }
    final groups = <_CapabilityGroup, List<DeviceTool>>{};
    for (final tool in tools) {
      groups.putIfAbsent(_CapabilityGroup.forTool(tool), () => []).add(tool);
    }
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.36,
      ),
      child: ListView(
        primary: false,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        children: [
          for (final group in _CapabilityGroup.values)
            if (groups[group] case final entries?) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(group.label, style: theme.textTheme.labelLarge),
              ),
              for (final tool in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        tool.description,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
