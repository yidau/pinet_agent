import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:piagent/mcp/operator_client.dart';

void main() {
  test(
    'streams the selected file with authorization and reports an existing name',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'piagent-upload-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/picked.tmp');
      final bytes = List.generate(128 * 1024, (index) => index % 256);
      await file.writeAsBytes(bytes);
      var calls = 0;
      final httpClient = MockClient((request) async {
        calls++;
        expect(
          request.url,
          Uri.parse('https://pi.example:8443/operator/captures/lab.pcap'),
        );
        expect(request.method, 'PUT');
        expect(request.headers['Authorization'], 'Bearer enrolled-phone');
        expect(request.headers['Content-Type'], 'application/octet-stream');
        expect(request.contentLength, bytes.length);
        expect(request.bodyBytes, bytes);
        expect(request.followRedirects, isFalse);
        return http.Response('{"message":"File already exists"}', 409);
      });
      final client = OperatorClient(
        httpClient,
        Uri.parse('https://pi.example:8443/mcp'),
        'enrolled-phone',
      );
      await expectLater(
        client.importFile(file, '../invalid.pcap'),
        throwsFormatException,
      );
      expect(calls, 0);
      await expectLater(
        client.importFile(file, 'lab.pcap'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'server reason',
            'File already exists',
          ),
        ),
      );
      expect(calls, 1);
    },
  );
}
