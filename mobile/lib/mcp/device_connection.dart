import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../network.dart';
import 'mcp_client.dart';
import 'operator_client.dart';
import 'tool_registry.dart';

enum DeviceConnectionStatus {
  disconnected,
  connecting,
  discovering,
  ready,
  error,
}

class DeviceConnection extends ChangeNotifier {
  DeviceConnectionStatus _status = DeviceConnectionStatus.disconnected;
  String? _error;
  String? _deviceName;
  DeviceSession? _session;
  McpClient? _client;
  int _connectionId = 0;
  bool _disposed = false;

  DeviceConnectionStatus get status => _status;
  String? get error => _error;
  String? get deviceName => _deviceName;
  DeviceSession? get session => _session;

  Future<void> connect({
    required Uri endpoint,
    required String token,
    required http.Client Function() createHttpClient,
  }) async {
    if (_disposed) return;
    final connectionId = ++_connectionId;
    final previous = _clearSession();
    if (previous != null) unawaited(previous.close());
    _update(DeviceConnectionStatus.connecting);
    if (connectionId != _connectionId) return;

    try {
      final client = McpClient(createHttpClient(), endpoint, token);
      if (connectionId != _connectionId) {
        await client.close();
        return;
      }
      _client = client;
      await client.initialize();
      if (connectionId != _connectionId) return;
      _deviceName = client.serverName;
      _update(DeviceConnectionStatus.discovering);
      if (connectionId != _connectionId) return;

      final entries = await client.listTools();
      if (connectionId != _connectionId) return;
      final registry =
          entries.any((entry) => entry['name'] == 'get_capability_status')
          ? await _discoverRegistry(client, entries)
          : ToolRegistry.fromTools(entries);
      if (connectionId != _connectionId) return;
      _session = DeviceSession._(this, client, entries, registry);
      _update(DeviceConnectionStatus.ready);
    } on McpConnectionException catch (error) {
      if (connectionId == _connectionId) _connectionFailed(error.message);
    } on FormatException catch (error) {
      if (connectionId == _connectionId) _connectionFailed(error.message);
    } catch (_) {
      if (connectionId == _connectionId) {
        _connectionFailed('连接失败，请检查设备地址和网络。');
      }
    }
  }

  Future<ToolRegistry> _discoverRegistry(
    McpClient client,
    List<Json> tools,
  ) async {
    final result = await client.callTool('get_capability_status', {});
    final entries = result['capabilities'];
    if (result['ok'] == false || entries is! List) {
      throw const FormatException('树莓派返回了无效的能力状态清单');
    }
    final kismet = result['kismet'];
    return ToolRegistry.fromTools(
      tools,
      capabilities: entries.map((entry) => jsonObject(entry, '工具状态')).toList(),
      phoneControl: result['operator_api'] == 1,
      kismet: kismet == null
          ? null
          : KismetStatus.fromJson(jsonObject(kismet, 'Kismet')),
    );
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    ++_connectionId;
    final client = _clearSession();
    _update(DeviceConnectionStatus.disconnected);
    await client?.close();
  }

  void _connectionFailed(String message) {
    ++_connectionId;
    final client = _clearSession();
    if (client != null) unawaited(client.close());
    _update(DeviceConnectionStatus.error, error: message);
  }

  McpClient? _clearSession() {
    final client = _client;
    _client = null;
    _session = null;
    _deviceName = null;
    return client;
  }

  void _update(DeviceConnectionStatus status, {String? error}) {
    _status = status;
    _error = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_connectionId;
    final client = _clearSession();
    _status = DeviceConnectionStatus.disconnected;
    _error = null;
    if (client != null) unawaited(client.close());
    super.dispose();
  }
}

class DeviceSession {
  DeviceSession._(
    this._connection,
    this._client,
    this._entries,
    this._registry,
  );

  final DeviceConnection _connection;
  final McpClient _client;
  final List<Json> _entries;
  ToolRegistry _registry;
  Future<void>? _refresh;

  ToolRegistry get registry => _registry;

  OperatorClient get operatorClient {
    _checkActive();
    if (!registry.phoneControl) throw const FormatException('当前设备未提供手机操作接口。');
    return _client.operatorClient;
  }

  Future<void> refreshCapabilities() {
    _checkActive();
    if (_registry.kismet == null) return Future.value();
    return _refresh ??= _refreshCapabilities().whenComplete(
      () => _refresh = null,
    );
  }

  Future<void> _refreshCapabilities() async {
    try {
      final fresh = await _connection._discoverRegistry(_client, _entries);
      _checkActive();
      _registry = fresh;
      _connection._update(DeviceConnectionStatus.ready);
    } on FormatException catch (error) {
      if (isActive) _connection._connectionFailed(error.message);
      rethrow;
    }
  }

  bool get isActive =>
      identical(_connection.session, this) &&
      _connection.status == DeviceConnectionStatus.ready;

  Future<Json> callTool(String name, Json arguments) async {
    _checkActive();
    registry.validateArguments(name, arguments);
    try {
      final result = await _client.callTool(name, arguments);
      _checkActive();
      return result;
    } on McpConnectionException catch (error) {
      _checkActive();
      _connection._connectionFailed(error.message);
      rethrow;
    }
  }

  void _checkActive() {
    if (!isActive) {
      throw const FormatException('设备连接已断开，无法调用工具。');
    }
  }
}
