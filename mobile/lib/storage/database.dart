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

Future<Database> openPiAgentDatabase(
  String fileName,
  OpenDatabaseOptions options,
) async {
  final DatabaseFactory factory;
  final String directory;
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) {
      throw StateError('LOCALAPPDATA is unavailable');
    }
    final store = Directory(path.join(localAppData, 'PiAgent'));
    await store.create(recursive: true);
    factory = _windowsDatabaseFactory;
    directory = store.path;
  } else {
    factory = databaseFactory;
    directory = await factory.getDatabasesPath();
  }
  return factory.openDatabase(path.join(directory, fileName), options: options);
}
