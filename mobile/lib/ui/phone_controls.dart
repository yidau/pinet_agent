import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../mcp/device_connection.dart';
import '../mcp/operator_client.dart';
import '../network.dart';

class PhoneControls extends StatefulWidget {
  const PhoneControls.radio({super.key, required this.session})
    : captures = null;
  const PhoneControls.captures({
    super.key,
    required this.session,
    required List<Json> files,
  }) : captures = files;

  final DeviceSession session;
  final List<Json>? captures;

  @override
  State<PhoneControls> createState() => _PhoneControlsState();
}

class _PhoneControlsState extends State<PhoneControls>
    with AutomaticKeepAliveClientMixin {
  static const _picker = MethodChannel('net.piagent.piagent/captures');
  Timer? _poll;
  Json _status = {};
  int _generation = 0;
  bool _busy = false;
  String? _message;
  String? _error;
  bool get _radio => widget.captures == null;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
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
    if (_running) {
      _poll = Timer(
        const Duration(seconds: 3),
        () => unawaited(_read(refresh: true)),
      );
    }
  }

  Future<void> _read({bool refresh = false}) async {
    final generation = ++_generation;
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
      if (refresh) await widget.session.refreshCapabilities();
    } on FormatException catch (error) {
      if (_current(generation)) setState(() => _error = error.message);
      return;
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
    if (mounted && widget.session.isActive && id != null) {
      await _command(PhoneAction.replayStart, {
        'capture_id': id,
        'confirm': true,
      });
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
              FilledButton.icon(
                icon: const Icon(Icons.wifi),
                label: const Text('扫描 Wi-Fi'),
                onPressed: _busy || _active(wifi['state'])
                    ? null
                    : () => _command(PhoneAction.wifiScan),
              ),
              OutlinedButton.icon(
                icon: Icon(btOn ? Icons.stop : Icons.bluetooth_searching),
                label: Text(btOn ? '停止蓝牙发现' : '开始蓝牙发现'),
                onPressed: _busy || bt['state'] == 'stopping'
                    ? null
                    : () => _command(
                        btOn
                            ? PhoneAction.bluetoothStop
                            : PhoneAction.bluetoothStart,
                      ),
              ),
            ],
          ),
          Text(
            'Wi-Fi · ${_label(wifi['state'])}${wifi['access_point_count'] is int && wifi['state'] == 'completed' ? " · ${wifi['access_point_count']} 个接入点" : ""}',
          ),
          if (wifi['reason'] case final String reason when reason.isNotEmpty)
            Text(reason),
          Text(
            '蓝牙 · ${_label(bt['state'])}${btOn && bt['remaining_seconds'] is int ? " · 剩余 ${bt['remaining_seconds']} 秒" : ""}',
          ),
          if (bt['reason'] case final String reason when reason.isNotEmpty)
            Text(reason),
        ] else ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (Platform.isAndroid)
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('从手机导入'),
                  onPressed: _busy ? null : _import,
                ),
              FilledButton.icon(
                icon: Icon(replaying ? Icons.stop : Icons.play_arrow),
                label: Text(replaying ? '停止重放' : '开始重放'),
                onPressed: _busy || (!replaying && widget.captures!.isEmpty)
                    ? null
                    : () {
                        if (replaying) {
                          unawaited(
                            _command(PhoneAction.replayStop, {'confirm': true}),
                          );
                        } else {
                          unawaited(_selectReplay());
                        }
                      },
              ),
            ],
          ),
          Text('文件重放 · ${_label(_status['state'])}'),
          if (_status['filename'] case final String file) Text(file),
          if (_status['datasource'] case final String uuid)
            SelectableText('数据源 $uuid'),
          if (_status['reason'] case final String reason when reason.isNotEmpty)
            Text(reason),
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
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        TextButton.icon(
          onPressed: _busy ? null : () => _read(refresh: true),
          icon: const Icon(Icons.refresh),
          label: const Text('刷新状态'),
        ),
      ],
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
