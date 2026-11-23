import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';
import 'dashboard_page.dart';
import 'message_repository.dart';
import 'proto/monitoring.pb.dart';
import 'telemetry_connection.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key, required this.connection});

  final TelemetryConnection connection;

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  final _scroll = ScrollController();
  String? _newest;

  @override
  void initState() {
    super.initState();
    widget.connection.addListener(_receive);
    _newest = widget.connection.messages.firstOrNull?.event.eventId;
  }

  @override
  void dispose() {
    widget.connection.removeListener(_receive);
    _scroll.dispose();
    super.dispose();
  }

  void _receive() {
    final newest = widget.connection.messages.firstOrNull?.event.eventId;
    final followLatest =
        _newest != newest &&
        TickerMode.valuesOf(context).enabled &&
        _scroll.hasClients &&
        _scroll.offset <= 56;
    setState(() => _newest = newest);
    if (followLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.connection;
    final events = feed.messages;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: ConsoleHeading(
            '${feed.unreadCount} 条未读',
            trailing: feed.phase == TelemetryPhase.live
                ? const Text('实时接收')
                : const Text('本地历史'),
          ),
        ),
        if (feed.storageError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '消息历史暂时无法保存或读取。',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              feed.isConfigured ? '当前没有事件记录。' : '扫码注册设备后接收事件。',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              key: const PageStorageKey('telemetry-messages'),
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final item = events[index];
                return _EventTile(
                  key: ValueKey(item.event.eventId),
                  item: item,
                  onTap: () => _openEvent(item),
                );
              },
            ),
          ),
      ],
    );
  }

  void _openEvent(StoredTelemetryEvent item) {
    unawaited(widget.connection.markRead(item));
    final event = item.event;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConsoleHeading(_eventTitle(event)),
              const SizedBox(height: 10),
              Text(
                '${_priorityLabel(event.priority)} · '
                '${formatTelemetryTime(event.timestampMs)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (event.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(event.description),
              ],
              if (event.source.isNotEmpty ||
                  event.bssid.isNotEmpty ||
                  event.evidenceId.isNotEmpty ||
                  event.occurrences > 1) ...[
                const SizedBox(height: 10),
                for (final value in [
                  if (event.source.isNotEmpty) '来源 · ${event.source}',
                  if (event.bssid.isNotEmpty) 'BSSID · ${event.bssid}',
                  if (event.evidenceId.isNotEmpty) '证据 · ${event.evidenceId}',
                  if (event.occurrences > 1) '观测次数 · ${event.occurrences}',
                ])
                  SelectableText(value),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({super.key, required this.item, required this.onTap});

  final StoredTelemetryEvent item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final event = item.event;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, color) = switch (event.priority) {
      EventPriority.P0 => (Icons.error_outline, colors.error),
      EventPriority.P1 => (
        Icons.warning_amber,
        ConsoleColors.warningOf(context),
      ),
      EventPriority.P2 => (Icons.info_outline, colors.primary),
      _ => (Icons.info_outline, colors.onSurfaceVariant),
    };
    return Material(
      color: colors.surfaceContainer,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, size: 21, color: color),
        title: Text(_eventTitle(event), style: theme.textTheme.titleSmall),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_priorityLabel(event.priority)} · '
              '${formatTelemetryTime(event.timestampMs)}'
              '${item.unread ? ' · 未读' : ''}',
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
            if (event.description.isNotEmpty)
              Text(
                event.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }
}

String _priorityLabel(EventPriority priority) => switch (priority) {
  EventPriority.P0 => 'P0 紧急',
  EventPriority.P1 => 'P1 重要',
  EventPriority.P2 => 'P2 一般',
  _ => 'P3 信息',
};

String _eventTitle(MonitoringEvent event) => switch (event.eventType) {
  'history_gap' => '事件历史有间隔',
  'capture_degraded' => '无线采集受限',
  'capture_recovered' || 'capture_available' => '无线采集可用',
  'resource_pressure' => '设备资源压力升高',
  'resource_recovered' => '设备资源压力恢复',
  'ap_discovered' => '观察到接入点',
  'priority_ap_observed' => '接入点进入重点观测列表',
  final kind when kind.startsWith('kismet_alert') => 'Kismet 无线告警',
  'policy_degraded' || 'sampling_degraded' => '无线摘要采样降频',
  'policy_recovered' || 'sampling_recovered' => '无线摘要采样恢复',
  'event_storage_recovered' => '设备事件存储恢复',
  _ => '设备事件',
};
