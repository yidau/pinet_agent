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
