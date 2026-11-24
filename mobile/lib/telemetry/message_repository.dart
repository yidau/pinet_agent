import 'package:fixnum/fixnum.dart';
import 'package:sqflite/sqflite.dart';

import '../storage/database.dart';
import 'proto/monitoring.pb.dart';

typedef EventCursor = ({String bootId, Int64 sequence});

class StoredTelemetryEvent {
  const StoredTelemetryEvent(this.event, {required this.unread});

  final MonitoringEvent event;
  final bool unread;
}

typedef HighRiskRecord = ({
  HighRiskEnvelope envelope,
  bool unread,
  String status,
});

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

  Future<Database> _open() => _opening ??=
      _openDatabase(
        OpenDatabaseOptions(
          version: 2,
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
            await _createHighRiskSchema(db);
          },
          onUpgrade: (db, oldVersion, _) async {
            if (oldVersion < 2) await _createHighRiskSchema(db);
          },
        ),
      ).then(
        (database) => database,
        onError: (Object error, StackTrace stack) {
          _opening = null;
          Error.throwWithStackTrace(error, stack);
        },
      );

  static Future<void> _createHighRiskSchema(Database db) async {
    await db.execute('''
      CREATE TABLE high_risk_archive (
        device_key TEXT NOT NULL,
        durable_id TEXT NOT NULL,
        payload BLOB,
        observed_at_ms INTEGER NOT NULL,
        unread INTEGER NOT NULL DEFAULT 1,
        user_status TEXT NOT NULL DEFAULT 'new',
        PRIMARY KEY (device_key, durable_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX high_risk_order ON high_risk_archive '
      '(device_key, observed_at_ms DESC, durable_id)',
    );
  }

  Future<bool> ingestHighRisk(
    String deviceKey,
    HighRiskEnvelope envelope,
  ) async {
    final db = await _open();
    return db.transaction((transaction) async {
      await transaction.insert('high_risk_archive', {
        'device_key': deviceKey,
        'durable_id': envelope.durableId,
        'payload': envelope.writeToBuffer(),
        'observed_at_ms':
            (envelope.event.hasObservedAtMs()
                    ? envelope.event.observedAtMs
                    : envelope.event.timestampMs)
                .toInt(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return Sqflite.firstIntValue(
            await transaction.rawQuery('SELECT changes()'),
          ) ==
          1;
    });
  }

  Future<List<HighRiskRecord>> highRiskPage(
    String deviceKey,
    int offset,
  ) async {
    final db = await _open();
    final rows = await db.query(
      'high_risk_archive',
      where: 'device_key = ? AND payload IS NOT NULL',
      whereArgs: [deviceKey],
      orderBy: 'observed_at_ms DESC, durable_id',
      limit: 30,
      offset: offset,
    );
    return [
      for (final row in rows)
        (
          envelope: HighRiskEnvelope.fromBuffer(row['payload']! as List<int>),
          unread: row['unread'] == 1,
          status: row['user_status']! as String,
        ),
    ];
  }

  Future<void> updateHighRisk(
    String deviceKey,
    String id, {
    String? status,
    bool delete = false,
  }) async {
    final db = await _open();
    await db.update(
      'high_risk_archive',
      {
        'unread': 0,
        if (status != null &&
            const {'new', 'acknowledged', 'resolved'}.contains(status))
          'user_status': status,
        // Keep only the key after deletion so a replay cannot resurrect the entry.
        if (delete) ...{
          'payload': null,
          'observed_at_ms': 0,
          'user_status': 'deleted',
        },
      },
      where: 'device_key = ? AND durable_id = ? AND payload IS NOT NULL',
      whereArgs: [deviceKey, id],
    );
  }

  Future<void> saveCursor(String deviceKey, EventCursor cursor) async {
    final db = await _open();
    await db.insert('cursors', {
      'device_key': deviceKey,
      'boot_id': cursor.bootId,
      'sequence': cursor.sequence.toInt(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

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
