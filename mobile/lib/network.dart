import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef Json = Map<String, dynamic>;

const bundledMcpUrl = String.fromEnvironment('PIAGENT_MCP_URL');

http.Client mcpHttpClient(Uri endpoint) {
  const certificate = String.fromEnvironment('PIAGENT_MCP_CA');
  if (certificate.isEmpty || endpoint != Uri.tryParse(bundledMcpUrl)) {
    return http.Client();
  }
  final context = SecurityContext()
    ..setTrustedCertificatesBytes(base64Decode(certificate));
  final client = HttpClient(context: context)..findProxy = (_) => 'DIRECT';
  return IOClient(client);
}

Uri serviceUri(String value) {
  final uri = Uri.tryParse(value.trim());
  const loopback = {'localhost', '127.0.0.1', '::1'};
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.hasQuery ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && loopback.contains(uri.host)))) {
    throw const FormatException('请输入 HTTPS 地址。本机调试可使用回环 HTTP 地址。');
  }
  return uri;
}

Json jsonObject(Object? value, String field) {
  if (value is! Json) {
    throw FormatException('响应字段无效（$field）');
  }
  return value;
}

Future<Json?> postJson(
  http.Client client,
  Uri url,
  Json body,
  Map<String, String> headers, {
  required String service,
  required Duration timeout,
  bool notification = false,
}) async {
  Future<Json?> send() async {
    final request = http.Request('POST', url)
      ..followRedirects = false
      ..headers.addAll({'Content-Type': 'application/json', ...headers})
      ..bodyBytes = utf8.encode(jsonEncode(body));
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FormatException('$service 请求失败（HTTP ${response.statusCode}）');
    }
    if (notification) {
      await response.stream.drain<void>();
      return null;
    }
    final contentType = response.headers.entries
        .where((entry) => entry.key.toLowerCase() == 'content-type')
        .firstOrNull
        ?.value
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (contentType != 'application/json') {
      throw FormatException('$service 返回了不兼容的内容类型');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw FormatException('$service 响应超过 1 MiB');
      }
      bytes.add(chunk);
    }
    return jsonObject(jsonDecode(utf8.decode(bytes.takeBytes())), service);
  }

  return send().timeout(
    timeout,
    onTimeout: () => throw FormatException('$service 请求超时'),
  );
}
