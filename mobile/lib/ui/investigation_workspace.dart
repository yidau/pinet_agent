import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../storage/history.dart';

/// The caller supplies entries from the currently connected device session.
String? latestEvidenceFinding(Iterable<ChatEntry> entries) {
  var hasEvidence = false;
  String? last;
  for (final entry in entries) {
    if (entry.role == 'user') {
      hasEvidence = false;
    } else if (entry.role == 'tool' && _returnedEvidence(entry)) {
      hasEvidence = true;
    } else if (entry.role == 'assistant' &&
        hasEvidence &&
        entry.text.trim().isNotEmpty) {
      last = entry.text;
      hasEvidence = false;
    }
  }
  return last;
}

bool _returnedEvidence(ChatEntry entry) {
  final details = entry.details?.trim();
  if (details == null || details.isEmpty) return false;
  try {
    final data = jsonDecode(details);
    if (data is Map) return data['ok'] != false && data['isError'] != true;
  } on FormatException {
    // Completed tools may return plain text or a truncated JSON preview.
  }
  return true;
}

class InvestigationWorkspace extends StatelessWidget {
  const InvestigationWorkspace({
    super.key,
    required this.entries,
    required this.draft,
    required this.activeTool,
    required this.busy,
    required this.loading,
    required this.historyWarning,
    required this.connected,
    required this.onSend,
  });

  final List<ChatEntry> entries;
  final TextEditingController draft;
  final String? activeTool;
  final bool busy;
  final bool loading;
  final bool historyWarning;
  final bool connected;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final turns = <List<ChatEntry>>[];
    for (final entry in entries) {
      if (turns.isEmpty || entry.role == 'user') turns.add([]);
      turns.last.add(entry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (historyWarning)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: Text('本地历史记录暂不可用。', style: theme.textTheme.bodySmall),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : turns.isEmpty
              ? _StartInvestigation(connected: connected, draft: draft)
              : ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  reverse: true,
                  itemCount: turns.length,
                  itemBuilder: (context, index) {
                    final turn = turns[turns.length - 1 - index];
                    return _Turn(key: ObjectKey(turn.first), entries: turn);
                  },
                ),
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      activeTool == null
                          ? '正在分析…'
                          : '正在${_toolTitle(activeTool!)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: draft,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 12000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      counterText: '',
                      hintText: '描述问题或下达分析任务…',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: IconButton.filled(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: '发送消息',
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(48),
                    ),
                    onPressed: busy || loading ? null : onSend,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StartInvestigation extends StatelessWidget {
  const _StartInvestigation({required this.connected, required this.draft});
  final bool connected;
  final TextEditingController draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.auto_awesome_outlined,
                color: colors.primary,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('调查当前网络', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          connected ? '从树莓派的观测记录中查找证据。' : '连接设备后，可调查热点、信号和设备告警。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (index, item) in const [
                (
                  Icons.radar,
                  '检查无线风险',
                  '请依据当前设备可用的接入点、安全配置和告警，说明哪些记录值得进一步核对，以及证据的局限。',
                ),
                (Icons.hub_outlined, '查看网络状态', '查看树莓派当前可用的网络信息，说明来源和观测时间。'),
                (Icons.memory, '查看系统状态', '查看树莓派的系统信息、CPU、内存、磁盘和温度。'),
              ].indexed) ...[
                if (index != 0) const Divider(height: 1),
                ListTile(
                  leading: Icon(item.$1, color: colors.primary, size: 21),
                  title: Text(item.$2, style: theme.textTheme.titleSmall),
                  trailing: Icon(
                    Icons.north_west,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  onTap: () => draft.value = TextEditingValue(
                    text: item.$3,
                    selection: TextSelection.collapsed(offset: item.$3.length),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

const _toolTitles = {
  'get_system_info': '读取系统信息',
  'get_cpu_info': '读取处理器状态',
  'get_memory_info': '读取内存状态',
  'get_disk_usage': '读取存储状态',
  'get_network_profile': '读取网络概况',
  'get_network_interfaces': '读取网络接口',
  'get_capability_status': '核对设备能力',
  'get_access_points': '获取接入点列表',
  'get_ap_details': '核对接入点详情',
  'get_wireless_clients': '读取无线客户端',
  'get_wifi_channels': '读取信道分布',
  'get_signal_history': '查询信号历史',
  'get_wireless_events': '读取无线事件',
  'get_kismet_alerts': '核对设备告警',
  'get_security_events': '读取安全事件',
  'get_kismet_devices': '读取观测设备',
  'get_kismet_status': '检查观测引擎',
  'get_kismet_version': '读取引擎版本',
  'get_kismet_datasources': '核对观测来源',
  'get_kismet_datasource_status': '核对来源状态',
  'get_kismet_capture_status': '读取采集状态',
  'scan_wireless_environment': '汇总已有无线观测',
  'get_bluetooth_devices': '读取蓝牙设备',
  'get_bluetooth_device_details': '读取蓝牙广播详情',
  'list_captures': '读取采集文件',
  'get_capture_metadata': '检查文件元信息',
  'get_capture_status': '读取离线重放状态',
};

String _toolName(String label) => label.split(' · ').first;
String _toolTitle(String label) =>
    _toolTitles[_toolName(label)] ?? _toolName(label);
bool _step(ChatEntry e) =>
    e.role == 'tool' ||
    (e.role == 'error' && (e.details != null || e.text.endsWith(' · 失败')));

class _Turn extends StatelessWidget {
  const _Turn({super.key, required this.entries});
  final List<ChatEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final steps = entries.where(_step).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries) ...[
          if (entry.role == 'user')
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 550),
                margin: const EdgeInsets.only(left: 28, top: 3, bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: SelectableText(
                  entry.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            )
          else if (_step(entry) && identical(entry, steps.first))
            _Evidence(steps: steps)
          else if (entry.role == 'assistant') ...[
            Row(
              children: [
                Icon(Icons.auto_awesome, color: colors.primary, size: 18),
                const SizedBox(width: 7),
                Text(
                  steps.isEmpty ? '助手回复' : '调查结果',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              entry.text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ] else if (entry.role == 'error' && !_step(entry))
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: colors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    entry.text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

class _Evidence extends StatelessWidget {
  const _Evidence({required this.steps});
  final List<ChatEntry> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final success = steps.where((s) => s.role == 'tool').length;
    final failed = steps.length - success;
    final summary = [
      if (success > 0) '$success 项完成',
      if (failed > 0) '$failed 项失败',
    ].join(' · ');
    final queries = steps
        .where((e) => e.role == 'tool')
        .map((e) => _toolTitle(e.text))
        .toSet()
        .take(3);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(steps.first),
        leading: Icon(
          Icons.fact_check_outlined,
          color: failed > 0 ? colors.error : colors.primary,
        ),
        title: Text('调查记录', style: theme.textTheme.titleSmall),
        subtitle: Text(
          [summary, if (queries.isNotEmpty) queries.join('、')].join('\n'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        children: [
          for (final step in steps)
            ListTile(
              leading: Icon(
                step.role == 'error'
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: step.role == 'error' ? colors.error : colors.primary,
                size: 20,
              ),
              title: Text(
                _toolTitle(step.text),
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                step.role == 'error'
                    ? '查询失败'
                    : step.details == null
                    ? '已完成 · 历史记录'
                    : '已完成 · 查看证据',
                style: theme.textTheme.bodySmall,
              ),
              trailing: step.details?.isNotEmpty == true
                  ? const Icon(Icons.chevron_right, size: 20)
                  : null,
              onTap: step.details?.isNotEmpty == true
                  ? () => _showEvidence(context, step)
                  : null,
            ),
        ],
      ),
    );
  }

  Future<void> _showEvidence(BuildContext context, ChatEntry step) {
    final theme = Theme.of(context);
    final raw = step.details!;
    String? source;
    String? time;
    try {
      final evidence = jsonDecode(raw);
      if (evidence is Map<String, dynamic>) {
        if (evidence['source'] case final String name when name.isNotEmpty) {
          source = name;
        }
        if (evidence['timestamp'] case final String stamp
            when stamp.isNotEmpty) {
          time = stamp;
        }
      }
    } on FormatException {
      // A recorded tool may return a plain-text or length-limited response.
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * .73,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(_toolTitle(step.text), style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(_toolName(step.text), style: theme.textTheme.bodySmall),
            if (source != null)
              Text('数据来源 · $source', style: theme.textTheme.bodySmall),
            if (time != null)
              Text('设备返回时间 · $time', style: theme.textTheme.bodySmall),
            const Divider(height: 24),
            SelectableText(
              raw,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
