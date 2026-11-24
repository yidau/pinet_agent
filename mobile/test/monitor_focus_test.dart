import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piagent/telemetry/monitor_focus.dart';
import 'package:piagent/telemetry/proto/monitoring.pb.dart';

void main() {
  test('active view requires nonzero bytes for a 30 second AP sample', () {
    final ap = ObservedDevice(kind: ObservedDeviceKind.AP);
    expect(hasRecentObservedTraffic(ap), isFalse);
    ap.traffic = ObservedTraffic(windowMs: 30000, observedBytes: Int64.ZERO);
    expect(hasRecentObservedTraffic(ap), isFalse);
    ap.traffic.observedBytes = Int64(1024);
    expect(hasRecentObservedTraffic(ap), isTrue);
    ap.traffic.windowMs = 5000;
    expect(hasRecentObservedTraffic(ap), isFalse);
  });

  test(
    'one observation combines every page and retains one total per SSID',
    () async {
      final now = Int64(2000);
      final first = ObservedDevicesPage(
        generation: Int64(3),
        sampledAtMs: now,
        nextPageToken: 'second',
        totalCount: 2,
        devices: [ObservedDevice(ssid: 'Lab', bssid: '00:00:00:00:00:01')],
        ssidTraffic: [SsidTraffic(ssid: 'Lab')],
      );
      final tokens = <String?>[];
      final snapshot = await readObservedSnapshot((token) async {
        tokens.add(token);
        return token == null
            ? first
            : ObservedDevicesPage(
                generation: Int64(3),
                sampledAtMs: now,
                totalCount: 2,
                devices: [
                  ObservedDevice(ssid: 'Lab', bssid: '00:00:00:00:00:02'),
                ],
                ssidTraffic: [SsidTraffic(ssid: 'Lab')],
              );
      }, isCurrent: () => true);
      expect(tokens, [null, 'second']);
      expect(snapshot!.devices.length, 2);
      expect(snapshot.ssidTraffic.length, 1);
      expect(snapshot.hasNextPageToken(), isFalse);
      expect(first.devices.length, 1);

      await expectLater(
        readObservedSnapshot(
          (token) async =>
              token == null ? first : ObservedDevicesPage(generation: Int64(4)),
          isCurrent: () => true,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'observed traffic distinguishes zero, partial and unavailable samples',
    () {
      final sample = ObservedTraffic(
        status: TrafficStatus.TRAFFIC_OBSERVED,
        observedBytes: Int64.ZERO,
        windowMs: 30000,
      );
      expect(observedTrafficLabel(sample, available: true), '30 秒观测 · 0 B');
      sample
        ..status = TrafficStatus.TRAFFIC_PARTIAL
        ..observedBytes = Int64(1536)
        ..estimated = true;
      expect(
        observedTrafficLabel(sample, available: true),
        '30 秒观测 · 约 1.5 KiB · 部分观测',
      );
      expect(observedTrafficLabel(sample, available: false), '观测流量暂不可用');
      expect(observedTrafficLabel(null, available: true), isNull);
      sample
        ..status = TrafficStatus.TRAFFIC_WARMING_UP
        ..clearObservedBytes();
      expect(observedTrafficLabel(sample, available: true), '等待 30 秒采样');
      sample.status = TrafficStatus.TRAFFIC_PROFILE_FILTERED;
      expect(observedTrafficLabel(sample, available: true), '轻量档未采集普通数据帧');
    },
  );

  test('SSID and BSSID focus both match the corresponding security event', () {
    const known = {'aa:bb:cc:dd:ee:ff': 'Guest-WiFi'};
    expect(
      focusMatchesBssid('aa:bb:cc:dd:ee:ff', {'SSID Guest-WiFi'}, known),
      isTrue,
    );
    expect(
      focusMatchesBssid('aa:bb:cc:dd:ee:ff', {
        'BSSID aa:bb:cc:dd:ee:ff',
      }, known),
      isTrue,
    );
    expect(
      focusMatchesBssid('aa:bb:cc:dd:ee:00', {'SSID Guest-WiFi'}, known),
      isFalse,
    );
    expect(
      focusMatchesBssid('aa:bb:cc:dd:ee:ff', {'SSID Other'}, known),
      isFalse,
    );
  });

  test('only fresh wireless samples trigger bounded automatic refresh', () {
    bool refresh({
      int sequence = 15,
      int lastRequest = 10,
      int latest = 2000,
      int loaded = 1000,
      bool visible = true,
      bool live = true,
      bool stale = false,
      bool loading = false,
      bool closed = false,
      bool busy = false,
      bool fallback = false,
    }) => shouldReloadObservedDevices(
      visible: visible,
      live: live,
      stale: stale,
      loading: loading,
      closed: closed,
      busy: busy,
      pressureFallback: fallback,
      currentSequence: sequence,
      lastRequestSequence: lastRequest,
      latestWirelessSampleMs: latest,
      loadedWirelessSampleMs: loaded,
    );
    expect(refresh(), isTrue);
    expect(refresh(sequence: 13), isFalse);
    expect(refresh(latest: 1000), isFalse);
    expect(refresh(fallback: true), isFalse);
    expect(refresh(visible: false), isFalse);
    expect(refresh(live: false), isFalse);
    expect(refresh(stale: true), isFalse);
    expect(refresh(loading: true), isFalse);
    expect(refresh(closed: true), isFalse);
    expect(refresh(busy: true), isFalse);
  });
}
