import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:piagent/enrollment/enrollment_profile.dart';
import 'package:piagent/main.dart';
import 'package:piagent/telemetry/dashboard_page.dart';
import 'package:piagent/telemetry/message_page.dart';
import 'package:piagent/telemetry/message_repository.dart';
import 'package:piagent/telemetry/normal_monitor_page.dart';
import 'package:piagent/telemetry/proto/monitoring.pbgrpc.dart';
import 'package:piagent/telemetry/telemetry_connection.dart';
import 'package:piagent/time_sync/automatic_time_sync.dart';
import 'package:piagent/ui/console_style.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqlite3/open.dart' as sqlite;

void main() {
  test(
    'the enrolled CA and bearer token open a TLS telemetry stream',
    () async {
      final fixtures = Directory('test/fixtures');
      final ca = await File(path.join(fixtures.path, 'loopback-ca.pem'))
          .readAsString();
      final profile = EnrollmentProfile.decode(
        {
          'device_id': 'fixture-phone',
          'token': 'fixture-token-abcdefghijklmnopqrstuvwxyz',
          'ssid': 'PocketNet fixture',
          'psk': 'fixture-password',
          'telemetry_url': 'https://127.0.0.1:9443',
          'ca_pem': ca,
        },
        piId: 'fixture-pi',
        fingerprint: 'sha256:${'a' * 64}',
        deviceName: 'Fixture phone',
      );
      final enrolled = TelemetryTarget.fromEnrollment(profile);
      expect(enrolled.port, 9443);

      final service = _LoopbackTelemetryService(enrolled.token);
      final server = Server.create(services: [service]);
      await server.serve(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        security: ServerTlsCredentials(
          certificate: await File(
            path.join(fixtures.path, 'loopback-server.pem'),
          ).readAsBytes(),
          privateKey: await File(
            path.join(fixtures.path, 'loopback-server-key.pem'),
          ).readAsBytes(),
        ),
      );
      addTearDown(() async {
        service.finish();
        await server.shutdown();
      });

      final feed = TelemetryConnection(repository: _repository());
      addTearDown(feed.dispose);
      feed.useTarget(
        TelemetryTarget(
          host: enrolled.host,
          port: server.port!,
          deviceKey: enrolled.deviceKey,
          phoneId: enrolled.phoneId,
          token: enrolled.token,
          caPem: enrolled.caPem,
        ),
      );

      await _until(() => feed.snapshot != null);
      expect(service.deviceId, profile.phoneId);
      expect(feed.snapshot!.bootId, 'loopback-boot');
      expect(feed.phase, TelemetryPhase.live);
      await feed.applyDefaultCaptureProfile();
      await feed.applyDefaultCaptureProfile();
      expect(service.profileRequests, [CaptureProfile.EXTENDED]);
      await feed.setProfile(CaptureProfile.LIGHT);
      await feed.applyDefaultCaptureProfile();
      expect(service.profileRequests, [
        CaptureProfile.EXTENDED,
        CaptureProfile.LIGHT,
      ]);

      service.policy = CapturePolicyStatus(
        actual: 'light',
        pressureForced: true,
      );
      feed.reconnect();
      await _until(() => feed.phase == TelemetryPhase.live);
      await feed.applyDefaultCaptureProfile();
      expect(service.profileRequests.length, 2);

      service.policy = CapturePolicyStatus(actual: 'light');
      feed.reconnect();
      await _until(() => feed.phase == TelemetryPhase.live);
      await feed.setProfile(CaptureProfile.BALANCED);
      await feed.applyDefaultCaptureProfile();
      expect(service.profileRequests, [
        CaptureProfile.EXTENDED,
        CaptureProfile.LIGHT,
        CaptureProfile.BALANCED,
      ]);
    },
  );

  test('automatic BLE time sync skips small offsets and preserves backward confirmation', () {
    expect(automaticTimeSyncWithoutWrite(-501), isNull);
    expect(
      automaticTimeSyncWithoutWrite(-500),
      AutomaticTimeSyncResult.aligned,
    );
    expect(automaticTimeSyncWithoutWrite(500), AutomaticTimeSyncResult.aligned);
    expect(
      automaticTimeSyncWithoutWrite(501),
      AutomaticTimeSyncResult.confirmBackward,
    );
  });

  testWidgets('reserved tabs show a placeholder without device actions', (
    tester,
  ) async {
    await tester.pumpWidget(const PocketNetApp());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('深度检测'));
    await tester.pumpAndSettle();
    expect(find.text('尚未开放'), findsOneWidget);
    await tester.tap(find.text('主动测试'));
    await tester.pumpAndSettle();
    expect(find.text('尚未开放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('high risk archive survives ordinary trimming and suppresses deleted replay', () async {
    final repository = _repository(limit: 2);
    final event = MonitoringEvent(
      eventId: 'unrelated-ordinary-id',
      timestampMs: Int64(10),
      eventCategory: EventCategory.SECURITY,
      riskClass: RiskClass.HIGH,
    );
    final envelope = HighRiskEnvelope(durableId: 'a' * 32, event: event);
    expect(await repository.ingestHighRisk('pi', envelope), isTrue);
    expect(await repository.ingestHighRisk('pi', envelope), isFalse);
    for (var i = 1; i <= 6; i++) {
      await repository.ingest('pi', MonitoringEvent(eventId: 'normal-$i'), (
        bootId: 'boot',
        sequence: Int64(i),
      ));
    }
    expect((await repository.load('pi')).messages.length, 2);
    expect(
      (await repository.highRiskPage('pi', 0)).single.envelope.durableId,
      envelope.durableId,
    );
    await repository.updateHighRisk('pi', envelope.durableId, delete: true);
    expect(await repository.ingestHighRisk('pi', envelope), isFalse);
    expect(await repository.highRiskPage('pi', 0), isEmpty);
  });

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
      expect(
        durable.messages.map((item) => item.event.eventId),
        contains('boot-a:4'),
      );
      expect(
        durable.messages.map((item) => item.event.eventId),
        contains('gap:boot-b:cursor_reset:0'),
      );
      await second.frames.close();
      await _until(() => sessions.length == 3);
      expect(sessions.last.request.lastBootId, 'boot-b');
      expect(sessions.last.request.lastEventSequence, Int64(1));
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
              system: SystemMetrics(
                cpuUsage: 22,
                temperatureC: 65,
                sampledAtMs: now,
              ),
              capture: CaptureMetrics(
                datasourceState: 'degraded',
                currentChannel: '36',
              ),
              deviceHealth: DeviceHealth(
                components: [
                  ComponentHealth(
                    componentId: ComponentId.ALERT_INPUT,
                    state: ComponentState.DEGRADED,
                    reason: 'polling_best_effort',
                    lastOkMs: now,
                  ),
                ],
              ),
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
    expect(find.text('设备在线，监听受限'), findsOneWidget);
    expect(find.text('22.0%'), findsOneWidget);
    expect(find.text('CPU 频率'), findsOneWidget);
    expect(find.text('当前信道'), findsOneWidget);
    final temperatureRow = find
        .ancestor(of: find.text('温度'), matching: find.byType(Row))
        .first;
    Finder temperatureIcon(IconData icon) =>
        find.descendant(of: temperatureRow, matching: find.byIcon(icon));
    expect(temperatureIcon(Icons.warning_rounded), findsOneWidget);
    final hotter = feed.snapshot!.deepCopy()..sequence = Int64(2);
    hotter.system.temperatureC = 75;
    await tester.runAsync(() async {
      transport.frames.add(TelemetryMessage(snapshot: hotter));
      await _until(() => feed.snapshot?.sequence == Int64(2));
    });
    await tester.pump();
    expect(temperatureIcon(Icons.error), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(420, 800));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('未知')).dy, greaterThan(770));
    await tester.binding.setSurfaceSize(const Size(320, 600));
    await tester.pumpAndSettle();
    expect(find.text('未报告'), findsWidgets);
    expect(find.text('重点接入点'), findsNothing);
    expect(find.textContaining('约每 3 秒'), findsNothing);
    await tester.tap(find.text('告警接入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('约每 3 秒'), findsOneWidget);
    expect(find.text('上次正常'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(MessagePage(connection: feed)));
    expect(find.text('1 条未读'), findsOneWidget);
    expect(find.text('无线采集受限'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('monitoring starts with active APs and opens all APs in place', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transport = _MemoryTransport();
    final now = Int64(1750000000000);
    ObservedDevice ap(String name, String mac, int bytes) => ObservedDevice(
      kind: ObservedDeviceKind.AP,
      ssid: name,
      bssid: mac,
      rssiDbm: -47,
      lastSeenMs: now,
      traffic: ObservedTraffic(
        status: TrafficStatus.TRAFFIC_OBSERVED,
        windowMs: 30000,
        observedBytes: Int64(bytes),
      ),
    );
    final feed = _ObservationFeed(
      repository: _repository(),
      createTransport: (_) => transport,
      page: (token) => ObservedDevicesPage(
        sampledAtMs: now,
        generation: Int64(1),
        totalCount: 2,
        nextPageToken: token == null ? 'second' : null,
        devices: token == null
            ? [ap('Active-WiFi', '20:00:00:00:00:01', 1536)]
            : [ap('Quiet-WiFi', '20:00:00:00:00:02', 0)],
      ),
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
      transport.frames.add(
        TelemetryMessage(
          snapshot: MonitoringSnapshot(
            bootId: 'boot-a',
            sequence: Int64(1),
            timestampMs: now,
            schemaVersion: 1,
            capabilityVersion: 2,
            wireless: WirelessSummary(
              sampledAtMs: now,
              coverage: 'live_source_window',
            ),
            capturePolicy: CapturePolicyStatus(actual: 'balanced'),
          ),
        ),
      );
      await _until(() => feed.phase == TelemetryPhase.live);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: consoleTheme(Brightness.dark),
        home: Scaffold(body: NormalMonitorPage(connection: feed, active: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('重点接入点'), findsOneWidget);
    expect(find.text('Quiet-WiFi'), findsNothing);
    expect(find.text('轻量'), findsNothing);
    expect(feed.requests, [null, 'second']);
    await tester.tap(find.text('查看所有'));
    await tester.pumpAndSettle();
    expect(find.text('所有接入点'), findsOneWidget);
    expect(find.text('Quiet-WiFi'), findsOneWidget);
    expect(find.text('加载下一页'), findsNothing);
    await tester.tap(find.text('20:00:00:00:00:02'));
    await tester.pumpAndSettle();
    expect(find.text('接入点详情'), findsOneWidget);
    expect(find.text('30 秒观测 · 0 B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ObservationFeed extends TelemetryConnection {
  _ObservationFeed({
    required super.repository,
    required super.createTransport,
    required this.page,
  });
  final ObservedDevicesPage Function(String?) page;
  final requests = <String?>[];

  @override
  Future<ObservedDevicesPage> observedDevices({
    String? token,
    String? ssid,
    String? bssid,
  }) async {
    requests.add(token);
    return page(token);
  }
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

class _LoopbackTelemetryService extends TelemetryServiceBase {
  _LoopbackTelemetryService(this.token);

  final String token;
  final _finished = Completer<void>();
  String? deviceId;
  CapturePolicyStatus policy = CapturePolicyStatus(actual: 'light');
  final profileRequests = <CaptureProfile>[];

  void finish() => _finished.complete();

  @override
  Future<AckHighRiskResponse> ackHighRisk(
    ServiceCall call,
    AckHighRiskRequest request,
  ) async => throw const GrpcError.unimplemented();

  @override
  Future<ObservedDevicesPage> getObservedDevices(
    ServiceCall call,
    ObservedDevicesRequest request,
  ) async => throw const GrpcError.unimplemented();

  @override
  Future<ControlCommandResponse> setCaptureProfile(
    ServiceCall call,
    SetCaptureProfileRequest request,
  ) async {
    profileRequests.add(request.targetProfile);
    return ControlCommandResponse(requestId: request.requestId, accepted: true);
  }

  @override
  Future<ControlCommandResponse> recoverComponent(
    ServiceCall call,
    RecoverComponentRequest request,
  ) async => throw const GrpcError.unimplemented();

  @override
  Stream<TelemetryMessage> subscribe(
    ServiceCall call,
    SubscribeRequest request,
  ) async* {
    if (call.clientMetadata?['authorization'] != 'Bearer $token') {
      throw const GrpcError.unauthenticated('Invalid fixture credentials');
    }
    deviceId = request.deviceId;
    yield TelemetryMessage(
      snapshot: MonitoringSnapshot(
        bootId: 'loopback-boot',
        schemaVersion: 1,
        sequence: Int64(1),
        capabilityVersion: 2,
        capturePolicy: policy,
      ),
    );
    await _finished.future;
  }
}
