import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../mcp/operator_client.dart';
import '../network.dart';
import 'console_style.dart';

class PhoneControls extends StatefulWidget {
  const PhoneControls.radio({
    super.key,
    required this.session,
    this.showBluetooth,
  }) : captures = null,
       importOnly = false,
       showImport = false;
  const PhoneControls.captures({
    super.key,
    required this.session,
    required List<Json> files,
    this.importOnly = false,
    this.showImport = true,
  }) : captures = files,
       showBluetooth = null;

  final DeviceSession session;
  final List<Json>? captures;
  final bool? showBluetooth;
  final bool importOnly;
  final bool showImport;

  @override
  State<PhoneControls> createState() => _PhoneControlsState();
}

class _PhoneControlsState extends State<PhoneControls>
    with AutomaticKeepAliveClientMixin {
  static const _picker = MethodChannel('net.piagent.piagent/captures');
  static const _pollInterval = Duration(seconds: 3);
  static const _idleStatusAge = Duration(seconds: 30);
  final _statusAge = Stopwatch();
  Timer? _poll;
  Json _status = {};
  int _generation = 0;
  int? _readingGeneration;
  bool _visible = false;
  bool _busy = false;
  String? _message;
  String? _error;
  bool get _radio => widget.captures == null;
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateVisibility();
  }

  void _updateVisibility({bool sessionChanged = false}) {
    final visible = TickerMode.valuesOf(context).enabled;
    if (_visible == visible && !sessionChanged) return;
    _visible = visible;
    _poll?.cancel();
    if (!visible ||
        widget.importOnly ||
        !widget.session.isActive ||
        _busy ||
        _readingGeneration == _generation) {
      return;
    }
    if (_running) {
      _schedule();
    } else if (!_statusAge.isRunning || _statusAge.elapsed >= _idleStatusAge) {
      unawaited(_read());
    }
  }

  @override
  void didUpdateWidget(PhoneControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.session, oldWidget.session) ||
        widget.importOnly != oldWidget.importOnly ||
        _radio != (oldWidget.captures == null)) {
      ++_generation;
      _poll?.cancel();
      _busy = false;
      _status = {};
      _message = null;
      _error = null;
      _statusAge
        ..stop()
        ..reset();
      _updateVisibility(sessionChanged: true);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool _current(int generation) =>
      mounted && widget.session.isActive && generation == _generation;
  bool _active(Object? state) =>
      const {'starting', 'running', 'stopping'}.contains(state);
  Json _radioInfo(String key) =>
      _status[key] is Json ? _status[key] as Json : {};
  bool get _running => _radio
      ? _active(_radioInfo('wifi')['state']) ||
            _active(_radioInfo('bluetooth')['state'])
      : _active(_status['state']);

  void _schedule() {
    _poll?.cancel();
    if (_visible && _running) {
      final remaining = _pollInterval - _statusAge.elapsed;
      _poll = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        () => unawaited(_read(refresh: true)),
      );
    }
  }

  Future<void> _read({bool refresh = false}) async {
    final generation = ++_generation;
    _readingGeneration = generation;
    _statusAge
      ..reset()
      ..start();
    _poll?.cancel();
    try {
      final reply = await widget.session.operatorClient.call(
        _radio ? PhoneAction.radioStatus : PhoneAction.replayStatus,
      );
      if (!_current(generation)) return;
      setState(() {
        _status = reply;
        _error = null;
      });
      _statusAge.reset();
      if (refresh) await widget.session.refreshCapabilities();
    } on FormatException catch (error) {
      if (_current(generation)) setState(() => _error = error.message);
      return;
    } finally {
      if (_readingGeneration == generation) _readingGeneration = null;
    }
    if (_current(generation)) _schedule();
  }

  Future<void> _command(PhoneAction action, [Json? body]) async {
    if (_busy) return;
    final generation = ++_generation;
    _poll?.cancel();
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    try {
      final reply = await widget.session.operatorClient.call(action, body);
      if (!_current(generation)) return;
      setState(() => _status = reply);
      _statusAge
        ..reset()
        ..start();
      await widget.session.refreshCapabilities();
    } on FormatException catch (error) {
      if (_current(generation)) setState(() => _error = error.message);
    } finally {
      if (_current(generation)) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Future<void> _confirmCommand({
    required PhoneAction action,
    required String title,
    required String explanation,
    required String confirm,
    Json? body,
  }) async {
    final session = widget.session;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    if (accepted == true &&
        mounted &&
        identical(widget.session, session) &&
        session.isActive) {
      await _command(action, body);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    final generation = ++_generation;
    _poll?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    File? staged;
    try {
      final selection = await _picker.invokeMapMethod<String, dynamic>('pick');
      if (selection == null) return;
      staged = File(selection['path'] as String);
      if (!mounted || !_current(generation)) return;
      final original = selection['name'] as String;
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _ImportName(original: original),
      );
      if (name == null || !_current(generation)) return;
      setState(() => _message = '正在导入 $name…');
      await widget.session.operatorClient.importFile(staged, name);
      if (!_current(generation)) return;
      setState(() => _message = '已导入 $name');
      await widget.session.refreshCapabilities();
    } on PlatformException catch (error) {
      if (_current(generation)) {
        setState(() => _error = error.message ?? '无法选择文件。');
      }
    } on FormatException catch (error) {
      if (_current(generation)) {
        setState(() {
          _error = error.message;
          _message = null;
        });
      }
    } on FileSystemException {
      if (_current(generation)) {
        setState(() {
          _error = '无法读取选中的文件。';
          _message = null;
        });
      }
    } finally {
      if (staged != null) {
        try {
          await staged.delete();
        } on FileSystemException {
          /* Android may clear its cache. */
        }
      }
      if (_current(generation)) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Future<void> _selectReplay() async {
    final session = widget.session;
    final id = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('选择要重放的文件')),
            for (final row in widget.captures!)
              if (row['id'] case final String id)
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: Text(row['filename']?.toString() ?? id),
                  onTap: () => Navigator.pop(sheet, id),
                ),
          ],
        ),
      ),
    );
    if (mounted &&
        identical(widget.session, session) &&
        session.isActive &&
        id != null) {
      await _confirmCommand(
        action: PhoneAction.replayStart,
        title: '重放这个文件？',
        explanation: '树莓派将在本机分析 $id，完成后会自动结束。',
        confirm: '确认重放',
        body: {'capture_id': id, 'confirm': true},
      );
    }
  }

  String _label(Object? state) => switch (state) {
    'idle' => '空闲',
    'starting' => '正在启动',
    'running' => '进行中',
    'stopping' => '正在停止',
    'completed' => '已完成',
    'stopped' => '已停止',
    'degraded' => '条件不足',
    'error' => '失败',
    null => '读取中',
    _ => state.toString(),
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wifi = _radioInfo('wifi');
    final bt = _radioInfo('bluetooth');
    final btOn = _active(bt['state']);
    final replaying = _active(_status['state']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_radio) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (widget.showBluetooth != true)
                FilledButton.icon(
                  icon: const Icon(Icons.wifi),
                  label: const Text('扫描 Wi-Fi'),
                  onPressed: _busy || _active(wifi['state'])
                      ? null
                      : () => _confirmCommand(
                          action: PhoneAction.wifiScan,
                          title: '发起一次 Wi-Fi 扫描？',
                          explanation: '树莓派将扫描附近接入点。与热点共用无线电时，手机连接可能短暂停顿。',
                          confirm: '确认扫描',
                        ),
                ),
              if (widget.showBluetooth != false)
                OutlinedButton.icon(
                  icon: Icon(btOn ? Icons.stop : Icons.bluetooth_searching),
                  label: Text(btOn ? '停止蓝牙发现' : '开始蓝牙发现'),
                  onPressed: _busy || bt['state'] == 'stopping'
                      ? null
                      : () => _confirmCommand(
                          action: btOn
                              ? PhoneAction.bluetoothStop
                              : PhoneAction.bluetoothStart,
                          title: btOn ? '停止本次蓝牙发现？' : '开始蓝牙发现？',
                          explanation: btOn
                              ? '本轮发现将结束。'
                              : '树莓派将发现附近的蓝牙设备，最长运行 120 秒，可随时停止。',
                          confirm: btOn ? '确认停止' : '确认开始',
                        ),
                ),
              _refreshButton(),
            ],
          ),
          if (widget.showBluetooth != true)
            _statusLine(
              'Wi-Fi',
              wifi,
              wifi['access_point_count'] is int && wifi['state'] == 'completed'
                  ? '${wifi['access_point_count']} 个接入点'
                  : null,
            ),
          if (widget.showBluetooth != false)
            _statusLine(
              '蓝牙',
              bt,
              btOn && bt['remaining_seconds'] is int
                  ? '剩余 ${bt['remaining_seconds']} 秒'
                  : null,
            ),
        ] else ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (widget.showImport && Platform.isAndroid)
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('从手机导入'),
                  onPressed: _busy ? null : _import,
                ),
              if (!widget.importOnly)
                FilledButton.icon(
                  icon: Icon(replaying ? Icons.stop : Icons.play_arrow),
                  label: Text(replaying ? '停止重放' : '开始重放'),
                  onPressed: _busy || (!replaying && widget.captures!.isEmpty)
                      ? null
                      : () {
                          if (replaying) {
                            unawaited(
                              _confirmCommand(
                                action: PhoneAction.replayStop,
                                title: '停止本次重放？',
                                explanation: '设备会结束当前文件的分析，原始文件将保留在树莓派上。',
                                confirm: '确认停止',
                                body: {'confirm': true},
                              ),
                            );
                          } else {
                            unawaited(_selectReplay());
                          }
                        },
                ),
              if (!widget.importOnly) _refreshButton(),
            ],
          ),
          if (widget.showImport && !Platform.isAndroid)
            const Text('从手机导入文件需要 Android 文件选择器。'),
          if (!widget.importOnly && !replaying && widget.captures!.isEmpty)
            const Text('先在「文件」中导入 PCAP 或 PCAPNG，即可启动离线重放。'),
          if (!widget.importOnly) _statusLine('文件重放', _status, null),
          if (_status['filename'] case final String file) Text(file),
          if (_status['datasource'] case final String uuid)
            SelectableText('数据源 $uuid'),
          if (_status['total_devices'] case final int count)
            Text('本次文件源观测到 $count 台设备'),
          if (_status['observed_devices'] case final List devices)
            for (final device in devices.whereType<Json>().take(5))
              Text(
                [device['name'], device['mac']].whereType<String>().join(' · '),
              ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Text(_message!),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _refreshButton() => IconButton(
    onPressed: _busy ? null : () => _read(refresh: true),
    tooltip: '刷新状态',
    icon: const Icon(Icons.refresh, size: 20),
  );

  Widget _statusLine(String title, Json data, String? detail) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final state = data['state'];
    final (icon, tone) = switch (state) {
      'error' => (Icons.error_outline, colors.error),
      'degraded' => (Icons.info_outline, ConsoleColors.warningOf(context)),
      'completed' => (
        Icons.check_circle_outline,
        ConsoleColors.successOf(context),
      ),
      'running' || 'starting' || 'stopping' => (Icons.sensors, colors.primary),
      _ => (Icons.radio_button_unchecked, colors.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  [title, _label(state), ?detail].join(' · '),
                  style: theme.textTheme.labelMedium?.copyWith(color: tone),
                ),
              ),
            ],
          ),
          if (data['reason'] case final String reason when reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 23),
              child: Text(
                reason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImportName extends StatefulWidget {
  const _ImportName({required this.original});
  final String original;
  @override
  State<_ImportName> createState() => _ImportNameState();
}

class _ImportNameState extends State<_ImportName> {
  late final _name = TextEditingController(text: _suggest(widget.original));
  String? _error;

  String _suggest(String source) {
    final dot = source.lastIndexOf('.');
    final extension = source.substring(dot).toLowerCase();
    final stem = source
        .substring(0, dot)
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceFirst(RegExp(r'^[^a-zA-Z0-9]+'), '');
    final base = stem.isEmpty ? 'capture' : stem;
    return base.substring(0, base.length.clamp(0, 96 - extension.length)) +
        extension;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('导入到树莓派'),
    content: TextField(
      controller: _name,
      maxLength: 96,
      decoration: InputDecoration(labelText: '文件名', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          if (!OperatorClient.filename.hasMatch(name) || name.length > 96) {
            setState(() => _error = '以字母或数字开头，使用英文文件名及 .pcap 或 .pcapng 扩展名。');
          } else {
            Navigator.pop(context, name);
          }
        },
        child: const Text('导入'),
      ),
    ],
  );
}
