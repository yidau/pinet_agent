import 'package:fixnum/fixnum.dart';
import 'package:sqflite/sqflite.dart';

import '../storage/history.dart';
import 'proto/monitoring.pb.dart';

typedef EventCursor = ({String bootId, Int64 sequence});

class StoredTelemetryEvent {
  const StoredTelemetryEvent(this.event, {required this.unread});

  final MonitoringEvent event;
  final bool unread;
}

class MessageRepository {
  MessageRepository({
    Future<Database> Function(OpenDatabaseOptions)? openDatabase,
    this.maximumEvents = 500,
  }) : _openDatabase =
           openDatabase ??
           ((options) => openPiAgentDatabase('telemetry.db', options)) {
    if (maximumEvents < 1 || maximumEvents > 500) {
      throw ArgumentError.value(maximumEvents, 'maximumEvents');
    }
  }

  final Future<Database> Function(OpenDatabaseOptions) _openDatabase;
  final int maximumEvents;
  Future<Database>? _opening;

  Future<Database> _open() => _opening ??= _openDatabase(
    OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_key TEXT NOT NULL,
            event_id TEXT NOT NULL,
            payload BLOB NOT NULL,
            unread INTEGER NOT NULL DEFAULT 1,
            UNIQUE(device_key, event_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE cursors (
            device_key TEXT NOT NULL PRIMARY KEY,
            boot_id TEXT NOT NULL,
            sequence INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX messages_device_order ON messages (device_key, id)',
        );
      },
    ),
  );

  Future<({EventCursor? cursor, List<StoredTelemetryEvent> messages})> load(
    String deviceKey,
  ) async {
    final db = await _open();
    final saved = await db.query(
      'cursors',
      where: 'device_key = ?',
      whereArgs: [deviceKey],
    );
    final rows = await db.query(
      'messages',
      where: 'device_key = ?',
      whereArgs: [deviceKey],
      orderBy: 'id DESC',
      limit: maximumEvents,
    );
    return (
      cursor: saved.isEmpty
          ? null
          : (
              bootId: saved.single['boot_id']! as String,
              sequence: Int64(saved.single['sequence']! as int),
            ),
      messages: [
        for (final row in rows)
          StoredTelemetryEvent(
            MonitoringEvent.fromBuffer(row['payload']! as List<int>),
            unread: row['unread'] == 1,
          ),
      ],
    );
  }

  // Persist the message and the completed replay position together.
  Future<bool> ingest(
    String deviceKey,
    MonitoringEvent event,
    EventCursor cursor,
  ) async {
    final db = await _open();
    return db.transaction((transaction) async {
      await transaction.insert('messages', {
        'device_key': deviceKey,
        'event_id': event.eventId,
        'payload': event.writeToBuffer(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      // Do not use the insert ID: SQLite may return the previous successful ID
      // after ignoring a duplicate.
      final changed = Sqflite.firstIntValue(
        await transaction.rawQuery('SELECT changes()'),
      );
      await transaction.insert('cursors', {
        'device_key': deviceKey,
        'boot_id': cursor.bootId,
        'sequence': cursor.sequence.toInt(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.rawDelete(
        '''
        DELETE FROM messages WHERE id < (
          SELECT id FROM messages ORDER BY id DESC LIMIT 1 OFFSET ?
        )
      ''',
        [maximumEvents - 1],
      );
      await transaction.rawDelete('''
        DELETE FROM cursors WHERE rowid < (
          SELECT rowid FROM cursors ORDER BY rowid DESC LIMIT 1 OFFSET 15
        )
      ''');
      return changed == 1;
    });
  }

  Future<void> markRead(String deviceKey, String eventId) async {
    final db = await _open();
    await db.update(
      'messages',
      {'unread': 0},
      where: 'device_key = ? AND event_id = ?',
      whereArgs: [deviceKey, eventId],
    );
  }
}
