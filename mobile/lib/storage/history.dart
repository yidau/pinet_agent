import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqlite3/open.dart' as sqlite;

final _windowsDatabaseFactory = ffi.createDatabaseFactoryFfi(
  ffiInit: _openWindowsSqlite,
);

void _openWindowsSqlite() {
  final systemRoot = Platform.environment['SystemRoot'];
  if (systemRoot == null || systemRoot.isEmpty) {
    throw StateError('Windows system directory is unavailable');
  }
  sqlite.open.overrideFor(
    sqlite.OperatingSystem.windows,
    () => DynamicLibrary.open(
      path.join(systemRoot, 'System32', 'winsqlite3.dll'),
    ),
  );
}

class ChatEntry {
  const ChatEntry(this.role, this.text, {this.details});

  final String role;
  final String text;
  final String? details;
}

class History {
  Future<Database>? _opening;

  Future<Database> _open() => _opening ??= _connect();

  Future<Database> _connect() async {
    final DatabaseFactory factory;
    final String directory;
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null || localAppData.isEmpty) {
        throw StateError('LOCALAPPDATA is unavailable');
      }
      final historyDir = Directory(path.join(localAppData, 'PiAgent'));
      await historyDir.create(recursive: true);
      factory = _windowsDatabaseFactory;
      directory = historyDir.path;
    } else {
      factory = databaseFactory;
      directory = await factory.getDatabasesPath();
    }
    return factory.openDatabase(
      path.join(directory, 'piagent.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE entries (
            id INTEGER PRIMARY KEY,
            role TEXT NOT NULL,
            text TEXT NOT NULL
          )
        '''),
      ),
    );
  }

  Future<List<ChatEntry>> load() async {
    final db = await _open();
    final rows = await db.query('entries', orderBy: 'id DESC', limit: 100);
    return [
      for (final row in rows.reversed)
        ChatEntry(row['role'] as String, row['text'] as String),
    ];
  }

  Future<void> add(ChatEntry entry) async {
    final db = await _open();
    await db.insert('entries', {'role': entry.role, 'text': entry.text});
  }
}
