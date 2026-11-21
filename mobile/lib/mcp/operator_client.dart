import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../network.dart';

enum PhoneAction {
  radioStatus('GET', 'radio/status'),
  wifiScan('POST', 'radio/wifi-scan'),
  bluetoothStart('POST', 'radio/bluetooth-start'),
  bluetoothStop('POST', 'radio/bluetooth-stop'),
  replayStatus('GET', 'replay/status'),
  replayStart('POST', 'replay/start'),
  replayStop('POST', 'replay/stop');

  const PhoneAction(this.method, this.path);
  final String method;
  final String path;
}

// File.openRead() supplies backpressure to the HTTP transport throughout the upload.
class _FileRequest extends http.BaseRequest with http.Abortable {
  _FileRequest(Uri url, this.file, this.abortTrigger) : super('PUT', url);
  final File file;
  @override
  final Future<void> abortTrigger;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(file.openRead());
  }
}

class OperatorClient {
  OperatorClient(this._http, this._endpoint, this._token);
  final http.Client _http;
  final Uri _endpoint;
  final String _token;
  final _active = <Completer<void>>{};
  bool _closed = false;

  static final filename = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._-]*\.(pcap|pcapng)$',
    caseSensitive: false,
  );

  Future<Json> call(PhoneAction action, [Json? body]) {
    final url = _endpoint.resolve('/operator/${action.path}');
    return _send((abort) {
      final request = http.AbortableRequest(
        action.method,
        url,
        abortTrigger: abort,
      );
      if (action.method == 'POST') {
        request.headers['Content-Type'] = 'application/json';
        request.bodyBytes = utf8.encode(
          jsonEncode(body ?? <String, dynamic>{}),
        );
      }
      return request;
    }, const Duration(seconds: 35));
  }

  Future<Json> importFile(File file, String name) async {
    if (!filename.hasMatch(name) || name.length > 96) {
      throw const FormatException('文件名无效。');
    }
    final size = await file.length();
    if (size < 1 || size > 64 * 1024 * 1024) {
      throw const FormatException('请选择 64 MiB 以内的非空文件。');
    }
    final url = _endpoint.resolve(
      '/operator/captures/${Uri.encodeComponent(name)}',
    );
    return _send(
      (abort) => _FileRequest(url, file, abort)
        ..contentLength = size
        ..headers['Content-Type'] = 'application/octet-stream',
      const Duration(minutes: 3),
    );
  }

  Future<Json> _send(
    http.BaseRequest Function(Future<void>) build,
    Duration timeout,
  ) async {
    if (_closed) throw const FormatException('设备已断开。');
    final abort = Completer<void>();
    _active.add(abort);
    try {
      final request = build(abort.future)
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'Bearer $_token',
          'Accept': 'application/json',
        });
      return await _read(request).timeout(timeout);
    } on TimeoutException {
      throw const FormatException('树莓派响应超时，请刷新状态。');
    } on http.ClientException {
      throw const FormatException('无法访问树莓派，请检查热点连接。');
    } on IOException {
      throw const FormatException('读取文件或连接树莓派失败。');
    } finally {
      _active.remove(abort);
      if (!abort.isCompleted) abort.complete();
    }
  }

  Future<Json> _read(http.BaseRequest request) async {
    final response = await _http.send(request);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('操作响应过大。');
      }
      bytes.add(chunk);
    }
    final success = response.statusCode >= 200 && response.statusCode < 300;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException('手机授权无效，请检查设备注册并重新连接。');
    }
    Json? data;
    try {
      final value = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (value is Json) data = value;
    } on FormatException {
      if (success) throw const FormatException('树莓派返回了无效的操作结果。');
    }
    if (!success) {
      throw FormatException(
        data?['message'] is String
            ? data!['message'] as String
            : '树莓派操作失败（HTTP ${response.statusCode}）。',
      );
    }
    return data ?? (throw const FormatException('树莓派返回了无效的操作结果。'));
  }

  void close() {
    _closed = true;
    for (final abort in _active) {
      if (!abort.isCompleted) abort.complete();
    }
  }
}
