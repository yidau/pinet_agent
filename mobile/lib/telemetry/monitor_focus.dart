import 'proto/monitoring.pb.dart';

String? observedTrafficLabel(
  ObservedTraffic? traffic, {
  required bool available,
}) {
  if (traffic == null) return null;
  if (!available) return '观测流量暂不可用';
  if (traffic.status == TrafficStatus.TRAFFIC_PROFILE_FILTERED) {
    return '轻量档未采集普通数据帧';
  }
  if (traffic.status == TrafficStatus.TRAFFIC_WARMING_UP) {
    return '等待 30 秒采样';
  }
  if (!traffic.hasObservedBytes()) return '暂无有效流量样本';

  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB'];
  var value = double.parse(traffic.observedBytes.toStringUnsigned());
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final precision = unit == 0 || value >= 100 ? 0 : 1;
  final quantity = '${value.toStringAsFixed(precision)} ${units[unit]}';
  final duration = traffic.windowMs ~/ 1000;
  final approximate = traffic.estimated ? '约 ' : '';
  final partial =
      traffic.status == TrafficStatus.TRAFFIC_PARTIAL ? ' · 部分观测' : '';
  return '$duration 秒观测 · $approximate$quantity$partial';
}

/// Rules are temporary UI preferences, not assertions that an AP is trusted.
bool focusMatchesBssid(
  String bssid,
  Set<String> focusRules,
  Map<String, String> observedSsids,
) {
  if (bssid.isEmpty) return false;
  if (focusRules.contains('BSSID $bssid')) return true;
  final ssid = observedSsids[bssid];
  return ssid != null && ssid.isNotEmpty && focusRules.contains('SSID $ssid');
}

/// Refresh no more frequently than once per four snapshots (~12 seconds).
/// When a user has paged past the first 32 rows, preserve the current view.
bool shouldReloadObservedDevices({
  required bool visible,
  required bool live,
  required bool stale,
  required bool loading,
  required bool closed,
  required bool busy,
  required bool pressureFallback,
  required int loadedCount,
  required int currentSequence,
  required int lastRequestSequence,
  required int latestWirelessSampleMs,
  required int loadedWirelessSampleMs,
}) {
  return visible &&
      live &&
      !stale &&
      !loading &&
      !closed &&
      !busy &&
      !pressureFallback &&
      loadedCount <= 32 &&
      currentSequence - lastRequestSequence >= 4 &&
      latestWirelessSampleMs > loadedWirelessSampleMs;
}
