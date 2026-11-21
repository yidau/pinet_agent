import 'package:http/http.dart' as http;

import '../network.dart';
import 'deepseek.dart';

class LlmClient {
  LlmClient(this._http, this.endpoint, this.apiKey, this.model);

  final http.Client _http;
  final Uri endpoint;
  final String apiKey;
  final String model;

  Future<Json> reply(List<Json> messages, List<Json> tools) async {
    final response = (await postJson(
      _http,
      endpoint,
      {
        'model': model,
        'messages': messages,
        if (tools.isNotEmpty) 'tools': tools,
        if (isDeepSeekEndpoint(endpoint)) 'thinking': {'type': 'disabled'},
      },
      {'Authorization': 'Bearer $apiKey', 'Accept': 'application/json'},
      service: '云端模型',
      timeout: const Duration(seconds: 75),
    ))!;
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('云端模型未返回可用的回复');
    }
    final choice = jsonObject(choices.first, 'choices');
    if (choice['finish_reason'] == 'length') {
      throw const FormatException('云端模型回复达到输出上限');
    }
    return jsonObject(choice['message'], 'message');
  }
}
