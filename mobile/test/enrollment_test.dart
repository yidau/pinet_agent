import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piagent/enrollment/enrollment_profile.dart';

void main() {
  test('a permanent registration QR validates the BLE service and secret', () {
    final secret = List<int>.generate(32, (index) => index);
    final fingerprint = 'sha256:${'a' * 64}';
    final payload = {
      'version': 1,
      'ble_service': enrollmentServiceUuid,
      'device_id': 'fixture-pi',
      'public_key_fingerprint': fingerprint,
      'enrollment_secret': enrollmentBase64(secret),
    };

    final qr = EnrollmentQr.parse(jsonEncode(payload));
    expect(qr.piId, 'fixture-pi');
    expect(qr.fingerprint, fingerprint);
    expect(qr.secret, secret);

    expect(
      () =>
          EnrollmentQr.parse(jsonEncode({...payload, 'ble_service': 'wrong'})),
      throwsFormatException,
    );
    expect(
      () => EnrollmentQr.parse(
        jsonEncode({
          ...payload,
          'enrollment_secret': enrollmentBase64([0]),
        }),
      ),
      throwsFormatException,
    );
  });
}
