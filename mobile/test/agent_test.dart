import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:piagent/agent/agent.dart';
import 'package:piagent/llm/llm_client.dart';
import 'package:piagent/mcp/mcp_client.dart';
import 'package:piagent/network.dart';

http.Response jsonResponse(Json payload, [int code = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(payload)),
      code,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );

void main() {
  test(
    'agent receives compiler diagnostics, writes a fix and checks CTest',
    () async {
      var modelTurn = 0;
      var initialized = false;
      var fixed = false;
      final calls = <String>[];
      final events = <ToolEvent>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Json;
        if (request.url.path == '/mcp') {
          expect(request.headers['Authorization'], 'Bearer device-token');
          final method = body['method'];
          Json result;
          switch (method) {
            case 'initialize':
              result = {'protocolVersion': '2025-11-25'};
            case 'notifications/initialized':
              expect(request.headers['MCP-Protocol-Version'], '2025-11-25');
              initialized = true;
              return http.Response('', 202);
            case 'tools/list':
              expect(initialized, isTrue);
              result = {
                'tools': [
                  for (final name in [
                    'compile_project',
                    'write_file',
                    'run_tests',
                    'execute_shell',
                  ])
                    {
                      'name': name,
                      'description': name,
                      'inputSchema': {'type': 'object'},
                    },
                ],
              };
            case 'tools/call':
              final params = body['params'] as Json;
              final name = params['name'] as String;
              calls.add(name);
              if (name == 'write_file') {
                fixed =
                    (params['arguments'] as Json)['content'] ==
                    'int main() { return 0; }';
                result = {
                  'structuredContent': {'bytes_written': 24},
                };
              } else {
                result = {
                  'structuredContent': {
                    'ok': fixed,
                    'stage': name == 'run_tests' ? 'test' : 'build',
                    'output': fixed
                        ? 'producer_consumer_queue passed'
                        : 'undeclared symbol',
                  },
                };
              }
            default:
              throw StateError('Unexpected MCP method $method');
          }
          return jsonResponse({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': result,
          });
        }
        expect(request.headers['Authorization'], 'Bearer llm-key');
        expect(request.body, isNot(contains('device-token')));
        expect(request.body, isNot(contains('execute_shell')));
        final messages = body['messages'] as List;
        final turn = modelTurn++;
        if (turn == 1) {
          expect(messages.last['content'], contains('undeclared symbol'));
        }
        if (turn == 4) {
          expect(
            messages.last['content'],
            contains('producer_consumer_queue passed'),
          );
        }
        final name = [
          'compile_project',
          'write_file',
          'compile_project',
          'run_tests',
          '',
        ][turn];
        return jsonResponse({
          'choices': [
            {
              'message': {
                'content': turn == 4 ? 'CTest 测试通过。' : null,
                if (turn < 4)
                  'tool_calls': [
                    {
                      'id': 'call-$turn',
                      'type': 'function',
                      'function': {
                        'name': name,
                        'arguments': jsonEncode(
                          name == 'write_file'
                              ? {
                                  'path': 'queue/main.cpp',
                                  'content': 'int main() { return 0; }',
                                }
                              : {'name': 'queue'},
                        ),
                      },
                    },
                  ],
              },
            },
          ],
        });
      });
      addTearDown(client.close);

      final agent = Agent(
        McpClient(client, Uri.parse('https://pi.example/mcp'), 'device-token'),
        LlmClient(
          client,
          Uri.parse('https://llm.example/chat/completions'),
          'llm-key',
          'model',
        ),
      );
      final answer = await agent.run('修复并测试队列', onEvent: events.add);
      expect(calls, [
        'compile_project',
        'write_file',
        'compile_project',
        'run_tests',
      ]);
      expect(
        events.where((event) => event.failed).single.output,
        'undeclared symbol',
      );
      expect(events.last.output, 'producer_consumer_queue passed');
      expect(answer, 'CTest 测试通过。');
    },
  );
}
