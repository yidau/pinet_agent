import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piagent/telemetry/monitor_focus.dart';
import 'package:piagent/telemetry/proto/monitoring.pb.dart';

void main() {
  test('observed traffic distinguishes zero, partial and unavailable samples', () {
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
  });

  test('SSID and BSSID focus both match the corresponding security event', () {
    const known = {'aa:bb:cc:dd:ee:ff': 'Guest-WiFi'};
    expect(focusMatchesBssid('aa:bb:cc:dd:ee:ff', {'SSID Guest-WiFi'}, known), isTrue);
    expect(focusMatchesBssid('aa:bb:cc:dd:ee:ff', {'BSSID aa:bb:cc:dd:ee:ff'}, known), isTrue);
    expect(focusMatchesBssid('aa:bb:cc:dd:ee:00', {'SSID Guest-WiFi'}, known), isFalse);
    expect(focusMatchesBssid('aa:bb:cc:dd:ee:ff', {'SSID Other'}, known), isFalse);
  });

  test('only fresh wireless samples trigger bounded automatic refresh', () {
    bool refresh({
      int sequence = 15, int lastRequest = 10,
      int latest = 2000, int loaded = 1000, int count = 32,
      bool visible = true, bool live = true, bool stale = false,
      bool loading = false, bool closed = false, bool busy = false,
      bool fallback = false,
    }) => shouldReloadObservedDevices(
      visible: visible, live: live, stale: stale, loading: loading,
      closed: closed, busy: busy, pressureFallback: fallback,
      loadedCount: count, currentSequence: sequence,
      lastRequestSequence: lastRequest, latestWirelessSampleMs: latest,
      loadedWirelessSampleMs: loaded,
    );
    expect(refresh(), isTrue);
    expect(refresh(sequence: 13), isFalse);
    expect(refresh(latest: 1000), isFalse);
    expect(refresh(count: 33), isFalse);
    expect(refresh(fallback: true), isFalse);
    expect(refresh(visible: false), isFalse);
    expect(refresh(live: false), isFalse);
    expect(refresh(stale: true), isFalse);
    expect(refresh(loading: true), isFalse);
    expect(refresh(closed: true), isFalse);
    expect(refresh(busy: true), isFalse);
  });
}
