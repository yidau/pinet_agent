import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:piagent/telemetry/dashboard_page.dart';
import 'package:piagent/telemetry/message_page.dart';
import 'package:piagent/telemetry/message_repository.dart';
import 'package:piagent/telemetry/proto/monitoring.pb.dart';
import 'package:piagent/telemetry/telemetry_connection.dart';
import 'package:piagent/ui/console_style.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqlite3/open.dart' as sqlite;

void main() {
  test(
    'telemetry resumes after a gap with the saved sequence and unread state',
    () async {
      final repository = _repository();
      final sessions = <_MemoryTransport>[];
      final feed = TelemetryConnection(
        repository: repository,
        createTransport: (_) {
          final transport = _MemoryTransport();
          sessions.add(transport);
          return transport;
        },
      );
      addTearDown(feed.dispose);
      const target = TelemetryTarget(
        host: 'localhost',
        deviceKey: 'test-device/test-phone',
        phoneId: 'test-phone',
        token: 'fixture-token',
        caPem: 'unused in memory transport',
      );
      feed.useTarget(target);
      await _until(() => sessions.isNotEmpty);
      final first = sessions.first;
      expect(first.request.deviceId, target.phoneId);
      expect(first.request.lastEventSequence, Int64.ZERO);
      final snapshot = MonitoringSnapshot(
        bootId: 'boot-a',
        schemaVersion: 1,
        sequence: Int64(1),
        latestEventSequence: Int64(10),
        system: SystemMetrics(cpuUsage: 0),
      );
      first.frames.add(
        TelemetryMessage.fromBuffer(
          TelemetryMessage(snapshot: snapshot).writeToBuffer(),
        ),
      );
      first.frames
        ..add(TelemetryMessage(event: _event(1)))
        ..add(TelemetryMessage(event: _event(1)))
        ..add(
          TelemetryMessage(
            historyGap: HistoryGap(
              bootId: 'boot-a',
              throughEventSequence: Int64(3),
              reason: 'history_pruned',
            ),
          ),
        )
        ..add(TelemetryMessage(event: _event(4)));
      await _until(() => feed.unreadCount == 3);
      expect(feed.snapshot!.system.hasCpuUsage(), isTrue);
      expect(feed.snapshot!.system.hasTemperatureC(), isFalse);
      expect(feed.messages.map((item) => item.event.eventId), [
        'boot-a:4',
        'gap:boot-a:history_pruned:3',
        'boot-a:1',
      ]);
      await feed.markRead(feed.messages.first);
      expect(feed.unreadCount, 2);
      expect(
        (await repository.load(target.deviceKey)).messages.first.unread,
        isFalse,
      );

      await first.frames.close();
      await _until(() => sessions.length == 2);
      final second = sessions.last;
      expect(second.request.lastBootId, 'boot-a');
      expect(second.request.lastEventSequence, Int64(4));
      second.frames
        ..add(
          TelemetryMessage(
            snapshot: MonitoringSnapshot.fromBuffer(snapshot.writeToBuffer())
              ..bootId = 'boot-b',
          ),
        )
        ..add(
          TelemetryMessage(
            historyGap: HistoryGap(
              bootId: 'boot-b',
              throughEventSequence: Int64.ZERO,
              reason: 'cursor_reset',
            ),
          ),
        )
        ..add(TelemetryMessage(event: _event(1, boot: 'boot-b')));
      await _until(() => feed.messages.first.event.eventId == 'boot-b:1');
      final durable = await repository.load(target.deviceKey);
      expect(durable.cursor, (bootId: 'boot-b', sequence: Int64(1)));
      expect(durable.messages.first.event.eventId, 'boot-b:1');
    },
  );

  test(
    'SQLite keeps only the newest messages and scopes records to a device',
    () async {
      final repository = _repository(limit: 2);
      const deviceA = 'pi-a/phone';
      const deviceB = 'pi-b/phone';
      final one = _event(1);
      final two = _event(2);
      final three = _event(3);
      EventCursor cursor(MonitoringEvent event) =>
          (bootId: event.bootId, sequence: event.sequence);
      expect(await repository.ingest(deviceA, one, cursor(one)), isTrue);
      expect(await repository.ingest(deviceA, one, cursor(one)), isFalse);
      await repository.ingest(deviceA, two, cursor(two));
      await repository.ingest(deviceB, three, cursor(three));
      final a = await repository.load(deviceA);
      final b = await repository.load(deviceB);
      expect(a.messages.single.event.eventId, two.eventId);
      expect(b.messages.single.event.eventId, three.eventId);
      expect(a.cursor, cursor(two));
      expect(b.cursor, cursor(three));
    },
  );

  testWidgets('compact dashboard reports missing metrics and shows events', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transport = _MemoryTransport();
    final feed = TelemetryConnection(
      repository: _repository(),
      createTransport: (_) => transport,
    );
    addTearDown(feed.dispose);
    await tester.runAsync(() async {
      feed.useTarget(
        const TelemetryTarget(
          host: 'localhost',
          deviceKey: 'fixture-device',
          phoneId: 'fixture-phone',
          token: 'fixture-token',
          caPem: 'unused',
        ),
      );
      await _until(() => transport.subscribed);
      final now = Int64(1750000000000);
      transport.frames
        ..add(
          TelemetryMessage(
            snapshot: MonitoringSnapshot(
              bootId: 'boot-a',
              sequence: Int64(1),
              schemaVersion: 1,
              timestampMs: now,
              system: SystemMetrics(cpuUsage: 22, sampledAtMs: now),
              capture: CaptureMetrics(datasourceState: 'degraded'),
            ),
          ),
        )
        ..add(TelemetryMessage(event: _event(1)));
      await _until(() => feed.unreadCount == 1);
    });
    Widget app(Widget page) => MaterialApp(
      theme: consoleTheme(Brightness.dark),
      home: Scaffold(body: page),
    );
    await tester.pumpWidget(
      app(DashboardPage(connection: feed, onOpenMessages: () {})),
    );
    expect(find.text('实时遥测'), findsOneWidget);
    expect(find.text('22.0%'), findsOneWidget);
    expect(find.text('未报告'), findsWidgets);
    await tester.pumpWidget(app(MessagePage(connection: feed)));
    expect(find.text('1 条未读'), findsOneWidget);
    expect(find.text('无线采集受限'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

MessageRepository _repository({int limit = 500}) {
  final factory = ffi.createDatabaseFactoryFfi(
    noIsolate: true,
    ffiInit: () {
      if (Platform.isWindows) {
        sqlite.open.overrideFor(
          sqlite.OperatingSystem.windows,
          () => DynamicLibrary.open(
            path.join(
              Platform.environment['SystemRoot']!,
              'System32',
              'winsqlite3.dll',
            ),
          ),
        );
      }
    },
  );
  return MessageRepository(
    maximumEvents: limit,
    openDatabase: (options) async {
      final db = await factory.openDatabase(
        ffi.inMemoryDatabasePath,
        options: options,
      );
      addTearDown(db.close);
      return db;
    },
  );
}

MonitoringEvent _event(int sequence, {String boot = 'boot-a'}) =>
    MonitoringEvent(
      bootId: boot,
      eventId: '$boot:$sequence',
      sequence: Int64(sequence),
      eventType: 'capture_degraded',
      priority: EventPriority.P1,
    );

Future<void> _until(bool Function() ready) =>
    Stream<void>.periodic(const Duration(milliseconds: 10))
        .firstWhere((_) => ready())
        .timeout(const Duration(seconds: 3));

class _MemoryTransport implements TelemetryTransport {
  final frames = StreamController<TelemetryMessage>();
  late SubscribeRequest request;
  bool subscribed = false;

  @override
  Stream<TelemetryMessage> subscribe(SubscribeRequest request) {
    this.request = request;
    subscribed = true;
    return frames.stream;
  }

  @override
  Future<void> close() async {
    if (!frames.isClosed) await frames.close();
  }
}
