import 'dart:io';

import 'package:path/path.dart' as path;

const deepSeekChatUrl = 'https://api.deepseek.com/chat/completions';
const deepSeekDefaultModel = 'deepseek-flash';

bool isDeepSeekEndpoint(Uri endpoint) =>
    endpoint.scheme == 'https' &&
    endpoint.host == 'api.deepseek.com' &&
    endpoint.port == 443;

Future<String?> readDeepSeekApiKey() async {
  if (!Platform.isWindows) return null;

  final executableDirectory = File(Platform.resolvedExecutable).parent;
  const filename = 'deepseekapi.txt';
  final candidates = {path.join(executableDirectory.path, filename)};

  for (var directory in [Directory.current, executableDirectory]) {
    while (true) {
      if (await File(path.join(directory.path, 'mobile', 'pubspec.yaml'))
              .exists() &&
          await File(path.join(directory.path, 'raspberry', 'requirements.txt'))
              .exists()) {
        candidates.add(path.join(directory.path, filename));
        break;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
  }

  try {
    for (final candidate in candidates) {
      final file = File(candidate);
      if (!await file.exists()) continue;
      if (await file.length() <= 1024) {
        final key = (await file.readAsString()).trim();
        if (RegExp(r'^sk-[A-Za-z0-9_-]+$').hasMatch(key)) return key;
      }
      throw const FormatException('deepseekapi.txt 应只包含一行 DeepSeek API Key。');
    }
  } on FileSystemException {
    throw const FormatException('无法读取本地 DeepSeek 密钥文件。');
  }
  return null;
}
