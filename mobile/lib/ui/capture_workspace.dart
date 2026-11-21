import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../network.dart';
import 'console_style.dart';
import 'phone_controls.dart';
import 'workspace_data.dart';

class CaptureWorkspace extends StatefulWidget {
  const CaptureWorkspace({
    super.key,
    required this.session,
    required this.observations,
  });
  final DeviceSession? session;
  final Map<String, Json> observations;
  @override
  State<CaptureWorkspace> createState() => _CaptureWorkspaceState();
}

class _CaptureWorkspaceState extends State<CaptureWorkspace> {
  bool _files = false;

  @override
  Widget build(BuildContext context) {
    final data = WorkspaceData(widget.session, widget.observations);
    final captures = data.rows('list_captures', 'captures');
    final usable = [
      for (final row in captures ?? const <Json>[])
        if (row['id'] is String &&
            (row['status'] == null || row['status'] == 'AVAILABLE'))
          row,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.sensors_outlined, size: 17),
              label: Text('采集会话'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.folder_outlined, size: 17),
              label: Text('PCAP 文件'),
            ),
          ],
          selected: {_files},
          onSelectionChanged: (selected) =>
              setState(() => _files = selected.single),
        ),
        const SizedBox(height: 16),
        if (_files)
          ..._fileWidgets(context, data, captures)
        else
          ..._sessionWidgets(context, data, usable),
      ],
    );
  }

  List<Widget> _fileWidgets(
    BuildContext context,
    WorkspaceData data,
    List<Json>? captures,
  ) {
    final session = widget.session;
    final library = data.result('list_captures');
    return [
      ConsoleHeading(
        '离线文件',
        trailing: captures == null ? null : Text('${captures.length} 个文件'),
      ),
      const SizedBox(height: 8),
      if (session?.registry.phoneControl == true) ...[
        ConsoleCard(
          child: PhoneControls.captures(
            key: ValueKey((session, 'import')),
            session: session!,
            files: captures ?? const [],
            importOnly: true,
          ),
        ),
        const SizedBox(height: 12),
      ],
      ConsoleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (captures?.isNotEmpty == true)
              for (var i = 0; i < captures!.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _FileTile(file: captures[i], data: data),
              ]
            else
              _Notice(
                icon: Icons.folder_open_outlined,
                title: captures == null ? '文件库暂不可用' : '文件库为空',
                detail: captures == null
                    ? data.reason('list_captures')
                    : session?.registry.phoneControl == true
                    ? '从手机导入 PCAP 或 PCAPNG，随后可查看元信息并重放。'
                    : '设备尚未返回可分析的离线文件。',
              ),
            if (library != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  evidenceLine(library),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _AnalysisPanel(data: data),
    ];
  }

  List<Widget> _sessionWidgets(
    BuildContext context,
    WorkspaceData data,
    List<Json> usable,
  ) {
    final session = widget.session;
    final sourceList = data.rows('get_kismet_datasources', 'datasources');
    final live = sourceList
        ?.where(
          (s) =>
              s['driver'] == 'linuxwifi' &&
              s['running'] == true &&
              s['paused'] != true &&
              s['error'] != true,
        )
        .toList();
    final replay = data.result('get_capture_status');
    final tasks = data.rows('list_captures', 'tasks');
    final hasFile = displayText(replay?['filename']) != null;
    return [
      ConsoleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Notice(
              icon: Icons.radio_button_checked,
              title: '实时采集',
              detail: session == null
                  ? '连接树莓派后可查看监听源和采集状态。'
                  : live?.isNotEmpty == true
                  ? 'Kismet 已连接 ${live!.length} 个活动 Wi-Fi 监听源。'
                  : '实时无线采集需要已配置的监听网卡和录制服务。',
            ),
            if (session != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '当前手机接口尚未提供实时录制的开始和停止操作。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (data.result('get_kismet_datasources') case final Json sources)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  evidenceLine(sources),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const ConsoleHeading('离线重放'),
      const SizedBox(height: 8),
      ConsoleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (session?.registry.phoneControl == true) ...[
              PhoneControls.captures(
                key: ValueKey((session, 'replay')),
                session: session!,
                files: usable,
                showImport: false,
              ),
              if (usable.isEmpty &&
                  replay?['state'] != 'running' &&
                  replay?['state'] != 'starting')
                TextButton.icon(
                  icon: const Icon(Icons.folder_open_outlined, size: 17),
                  onPressed: () => setState(() => _files = true),
                  label: const Text('前往 PCAP 文件'),
                ),
            ] else if (replay != null) ...[
              _Notice(
                icon: Icons.replay_outlined,
                title: _state(replay['state']),
                detail:
                    displayText(replay['reason']) ??
                    (session == null ? '连接设备后查看重放记录。' : '可查看设备返回的文件重放状态。'),
              ),
              if (displayText(replay['datasource']) case final String uuid)
                SelectableText(
                  uuid,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ] else
              _Notice(
                icon: Icons.replay_outlined,
                title: '重放状态未就绪',
                detail: data.reason('get_capture_status'),
              ),
            if (replay != null)
              Text(
                evidenceLine(replay),
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const ConsoleHeading('会话记录'),
      const SizedBox(height: 8),
      ConsoleCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasFile) _Record(row: replay!, isReplay: true),
            if (tasks?.isNotEmpty == true)
              for (final task in tasks!) _Record(row: task),
            if (tasks == null || tasks.isEmpty)
              Text(
                hasFile
                    ? '设备仅保留最近一次文件重放状态。'
                    : session == null
                    ? '连接设备后可读取会话记录。'
                    : tasks?.isEmpty == true
                    ? '设备返回的采集会话为空。'
                    : '设备当前未提供历史采集会话列表。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    ];
  }
}

String _state(Object? state) => switch (state) {
  'idle' => '空闲',
  'starting' => '正在启动',
  'running' => '进行中',
  'completed' => '已完成',
  'stopped' => '已停止',
  'stopping' => '正在停止',
  'error' => '失败',
  _ => displayText(state) ?? '状态未报告',
};

class _Record extends StatelessWidget {
  const _Record({required this.row, this.isReplay = false});
  final Json row;
  final bool isReplay;
  @override
  Widget build(BuildContext context) {
    final start = deviceTime(row['started'] ?? row['started_at']);
    final seconds = row['duration_seconds'];
    final description = [
      if (isReplay) '离线重放',
      ?displayText(row['interface']),
      if (start != null) '开始于 ${displayTime(start)}',
      if (seconds is int && seconds >= 0)
        '时长 ${seconds ~/ 60} 分 ${seconds % 60} 秒',
      ?displayBytes(row['size_bytes']),
      if (displayText(row['source']) case final String source)
        sourceName(source),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayText(row['filename'] ?? row['name'] ?? row['id']) ?? '采集会话',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(_state(row['state'] ?? row['status'])),
          if (description.isNotEmpty)
            Text(
              description.join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary, size: 23),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.data});
  final Json file;
  final WorkspaceData data;
  @override
  Widget build(BuildContext context) {
    final session = data.session;
    final id = displayText(file['id']);
    final valid = file['status'] == null || file['status'] == 'AVAILABLE';
    final time = deviceTime(file['modified_at']);
    final canInspect =
        session?.registry['get_capture_metadata']?.isCallable == true &&
        id != null &&
        valid;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        valid ? Icons.insert_drive_file_outlined : Icons.warning_amber_outlined,
        color: valid
            ? Theme.of(context).colorScheme.primary
            : ConsoleColors.warningOf(context),
      ),
      title: Text(
        displayText(file['filename'] ?? file['name']) ?? '文件',
        softWrap: true,
      ),
      subtitle: Text(
        [
          ?displayText(file['format']),
          ?displayBytes(file['size_bytes']),
          if (time != null) '修改于 ${displayTime(time)}',
          if (!valid) displayText(file['reason']) ?? '文件无法读取',
          if (valid && !canInspect) data.reason('get_capture_metadata'),
        ].join(' · '),
      ),
      trailing: canInspect ? const Icon(Icons.chevron_right, size: 19) : null,
      onTap: canInspect ? () => _metadata(context, session!, id) : null,
    );
  }
}

Future<void> _metadata(BuildContext context, DeviceSession session, String id) {
  final query = session
      .callTool('get_capture_metadata', {'capture_id': id})
      .onError<FormatException>(
        (error, _) => {'ok': false, 'message': error.message},
      );
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('文件元信息'),
      content: SingleChildScrollView(
        child: FutureBuilder<Json>(
          future: query,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            if (!session.isActive) return const Text('设备已断开。');
            final raw = snapshot.data;
            if (raw == null || raw['ok'] == false) {
              return Text(displayText(raw?['message']) ?? '读取元信息失败。');
            }
            final file = raw['data'] is Json ? raw['data'] as Json : raw;
            final modified = deviceTime(file['modified_at']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (label, value) in [
                  ('文件', displayText(file['filename'])),
                  ('格式', displayText(file['format'])),
                  ('大小', displayBytes(file['size_bytes'])),
                  ('修改时间', modified == null ? null : displayTime(modified)),
                ])
                  if (value != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          SelectableText(value),
                        ],
                      ),
                    ),
                Text(
                  evidenceLine(file),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _AnalysisPanel extends StatelessWidget {
  const _AnalysisPanel({required this.data});
  final WorkspaceData data;
  @override
  Widget build(BuildContext context) {
    final report = data.result('analyze_packet_capture');
    final protocols = data.rows('analyze_protocol_distribution', 'protocols');
    return ConsoleCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        showTrailingIcon: true,
        leading: Icon(
          Icons.analytics_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text('分析结果'),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('文件摘要', style: Theme.of(context).textTheme.titleSmall),
                Text(
                  displayText(report?['summary']) ??
                      data.reason('analyze_packet_capture'),
                ),
                if (report != null)
                  Text(
                    evidenceLine(report),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                Text('协议统计', style: Theme.of(context).textTheme.titleSmall),
                if (protocols == null)
                  Text(data.reason('analyze_protocol_distribution'))
                else if (protocols.isEmpty)
                  const Text('设备未返回协议记录。')
                else
                  for (final row in protocols)
                    Text(
                      [
                        ?displayText(row['protocol']),
                        if (row['packet_count'] case final int n) '$n 个报文',
                      ].join(' · '),
                    ),
                if (data.result('analyze_protocol_distribution')
                    case final Json reply)
                  Text(
                    evidenceLine(reply),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
