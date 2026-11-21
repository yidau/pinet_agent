import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;

import '../network.dart';

const enrollmentServiceUuid = '7ab410a0-fd6a-49f1-91bb-40e71e672100';
const _invalidQr = FormatException('这不是有效的 PiAgent 永久二维码。');
const _invalidProfile = FormatException('树莓派返回的注册信息无效。');
final _identityPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$');
final _fingerprintPattern = RegExp(r'^sha256:[a-f0-9]{64}$');
final _base64UrlPattern = RegExp(r'^[A-Za-z0-9_-]+$');

String enrollmentBase64(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

Uint8List enrollmentBytes(String value, {int? length, int? maxLength}) {
  if (!_base64UrlPattern.hasMatch(value) ||
      value.length > ((maxLength ?? length ?? 128) * 4 + 2) ~/ 3) {
    throw const FormatException('注册数据编码无效。');
  }
  final decoded = base64Url.decode(base64Url.normalize(value));
  if ((length != null && decoded.length != length) ||
      (maxLength != null && decoded.length > maxLength) ||
      enrollmentBase64(decoded) != value) {
    throw const FormatException('注册数据编码无效。');
  }
  return decoded;
}

class EnrollmentQr {
  const EnrollmentQr._(this.piId, this.fingerprint, this.secret);

  factory EnrollmentQr.parse(String text) {
    try {
      if (text.length > 1024) throw _invalidQr;
      final json = jsonDecode(text);
      if (json is! Json ||
          json['version'] != 1 ||
          json['ble_service'] != enrollmentServiceUuid) {
        throw _invalidQr;
      }
      final piId = json['device_id'];
      final fingerprint = json['public_key_fingerprint'];
      final secret = json['enrollment_secret'];
      if (piId is! String ||
          !_identityPattern.hasMatch(piId) ||
          fingerprint is! String ||
          !_fingerprintPattern.hasMatch(fingerprint) ||
          secret is! String) {
        throw _invalidQr;
      }
      return EnrollmentQr._(
        piId,
        fingerprint,
        enrollmentBytes(secret, length: 32),
      );
    } on FormatException {
      throw _invalidQr;
    }
  }

  final String piId;
  final String fingerprint;
  final Uint8List secret;
}

class EnrollmentProfile {
  const EnrollmentProfile._(
    this.piId,
    this.fingerprint,
    this.phoneId,
    this.deviceName,
    this.token,
    this.ssid,
    this.psk,
    this.mcpUrl,
    this.caPem,
  );

  factory EnrollmentProfile.decode(
    Json json, {
    required String piId,
    required String fingerprint,
    required String deviceName,
  }) {
    final phoneId = json['device_id'];
    final token = json['token'];
    final ssid = json['ssid'];
    final psk = json['psk'];
    final mcpUrl = json['mcp_url'];
    final caPem = json['ca_pem'];
    if (!_identityPattern.hasMatch(piId) ||
        !_fingerprintPattern.hasMatch(fingerprint) ||
        deviceName.isEmpty ||
        utf8.encode(deviceName).length > 64 ||
        phoneId is! String ||
        !_identityPattern.hasMatch(phoneId) ||
        token is! String ||
        token.length < 32 ||
        token.length > 256 ||
        !_base64UrlPattern.hasMatch(token) ||
        ssid is! String ||
        ssid.isEmpty ||
        utf8.encode(ssid).length > 32 ||
        psk is! String ||
        psk.length < 8 ||
        psk.length > 64 ||
        mcpUrl is! String ||
        mcpUrl.length > 512 ||
        caPem is! String ||
        caPem.length > 32768 ||
        !caPem.startsWith('-----BEGIN CERTIFICATE-----')) {
      throw _invalidProfile;
    }
    final endpoint = serviceUri(mcpUrl);
    if (endpoint.scheme != 'https' || endpoint.path != '/mcp') {
      throw _invalidProfile;
    }
    return EnrollmentProfile._(
      piId,
      fingerprint,
      phoneId,
      deviceName,
      token,
      ssid,
      psk,
      endpoint,
      caPem,
    );
  }

  static const _platform = MethodChannel('net.piagent.piagent/enrollment');

  static Future<EnrollmentProfile?> load() async {
    final data = await _platform.invokeMethod<String>('loadProfile');
    if (data == null) return null;
    final map = jsonObject(jsonDecode(data), 'profile');
    final piId = map['pi_id'];
    final fingerprint = map['public_key_fingerprint'];
    final name = map['device_name'];
    if (piId is! String || fingerprint is! String || name is! String) {
      throw _invalidProfile;
    }
    return EnrollmentProfile.decode(
      map,
      piId: piId,
      fingerprint: fingerprint,
      deviceName: name,
    );
  }

  Future<void> save() => _platform.invokeMethod<void>('saveProfile', {
    'data': jsonEncode({
      'pi_id': piId,
      'public_key_fingerprint': fingerprint,
      'device_id': phoneId,
      'device_name': deviceName,
      'token': token,
      'ssid': ssid,
      'psk': psk,
      'mcp_url': mcpUrl.toString(),
      'ca_pem': caPem,
    }),
  });

  Future<bool> connectWifi() async =>
      await _platform.invokeMethod<bool>('connectWifi', {
        'ssid': ssid,
        'password': psk,
      }) ??
      false;

  final String piId;
  final String fingerprint;
  final String phoneId;
  final String deviceName;
  final String token;
  final String ssid;
  final String psk;
  final Uri mcpUrl;
  final String caPem;
}
