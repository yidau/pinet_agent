import '../network.dart';
import 'workspace_data.dart';

/// A projection of one device report. New servers supply the SSID membership;
/// older servers supply AP rows only.
class WifiNetworks {
  WifiNetworks(Json report, List<Json> rows) {
    final canonical = report['networks'] is List;
    for (final row in rows) {
      final address = wifiBssid(row);
      if (address == null) continue;
      final previous = byBssid[address];
      if (previous == null) {
        byBssid[address] = {
          ...row,
          'bssid': address,
          if (!canonical) 'first_seen': row['first_seen'] ?? row['observed_at'],
        };
        continue;
      }
      final oldTime = wifiLastSeen(previous);
      final newTime = wifiLastSeen(row);
      final newest =
          newTime != null && (oldTime == null || !newTime.isBefore(oldTime))
          ? row
          : previous;
      final sources = {...wifiSources(previous), ...wifiSources(row)};
      final previousFirst = previous['first_seen'];
      final first = row['first_seen'] ?? row['observed_at'];
      final previousDate = deviceTime(previousFirst),
          firstDate = deviceTime(first);
      byBssid[address] = {
        ...newest,
        'bssid': address,
        'observation_sources': sources.toList(),
        if (!canonical)
          'first_seen':
              firstDate != null &&
                  (previousDate == null || firstDate.isBefore(previousDate))
              ? first
              : previousFirst,
      };
    }
    final claimed = <String>{};
    final serverGroups = report['networks'];
    if (serverGroups is List) {
      for (final entry in serverGroups.whereType<Json>()) {
        final members = entry['bssids'];
        if (members is! List) continue;
        final aps = <Json>[];
        for (final value in members.whereType<String>()) {
          final address = value.toLowerCase();
          final ap = byBssid[address];
          if (ap != null && claimed.add(address)) aps.add(ap);
        }
        if (aps.isNotEmpty) _addGroup(wifiSsid(entry), aps);
      }
    }
    for (final entry in byBssid.entries) {
      if (!claimed.contains(entry.key)) {
        _addGroup(wifiSsid(entry.value), [entry.value]);
      }
    }
  }

  final byBssid = <String, Json>{};
  // Tag named and hidden identities separately: an SSID may itself resemble a MAC.
  final _members = <(String?, String?), List<Json>>{};

  void _addGroup(String? ssid, List<Json> aps) {
    for (final ap in aps) {
      final key = (ssid, ssid == null ? wifiBssid(ap) : null);
      (_members[key] ??= []).add(ap);
    }
  }

  List<WifiNetwork> groups(String? band) {
    final result = <WifiNetwork>[];
    for (final entry in _members.entries) {
      final aps = entry.value
          .where((row) => band == null || wifiBand(row) == band)
          .toList();
      if (aps.isNotEmpty) result.add(WifiNetwork(entry.key.$1, aps));
    }
    result.sort((a, b) {
      final strength = (b.strongest ?? double.negativeInfinity).compareTo(
        a.strongest ?? double.negativeInfinity,
      );
      return strength == 0 ? a.title.compareTo(b.title) : strength;
    });
    return result;
  }
}

class WifiNetwork {
  WifiNetwork(this.ssid, this.aps);
  final String? ssid;
  final List<Json> aps;
  String get title => ssid ?? '隐藏网络 · ${aps.first['bssid']}';
  Set<String> get channels => {for (final ap in aps) ?wifiChannel(ap)};
  Iterable<num> get signals => aps
      .map((ap) => ap['rssi_dbm'])
      .whereType<num>()
      .where((value) => value.isFinite);
  late final num? strongest = signals.fold<num?>(
    null,
    (old, v) => old == null || v > old ? v : old,
  );
  late final num? weakest = signals.fold<num?>(
    null,
    (old, v) => old == null || v < old ? v : old,
  );
  late final DateTime? lastSeen = aps
      .map(wifiLastSeen)
      .whereType<DateTime>()
      .fold<DateTime?>(
        null,
        (old, v) => old == null || v.isAfter(old) ? v : old,
      );
}

final _mac = RegExp(r'^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$');
String? wifiBssid(Json row) {
  for (final value in [row['bssid'], row['mac'], row['id']]) {
    if (value is! String) continue;
    final address = value.toLowerCase().replaceAll('-', ':');
    if (_mac.hasMatch(address)) return address;
  }
  return null;
}

String? wifiSsid(Json row) {
  final value = row.containsKey('ssid') ? row['ssid'] : row['name'];
  if (value is! String || value.isEmpty) return null;
  // Old Kismet views sometimes substitute the MAC as the device name.
  if (!row.containsKey('ssid') && value.toLowerCase() == wifiBssid(row)) {
    return null;
  }
  return value;
}

Iterable<String> wifiSources(Json row) sync* {
  final list = row['observation_sources'];
  if (list is List) yield* list.whereType<String>();
  if (row['observation_source'] case final String source) yield source;
  if (row['source'] case final String source) yield source;
}

DateTime? wifiLastSeen(Json row) =>
    deviceTime(row['last_seen'] ?? row['observed_at']);
String? wifiChannel(Json row) {
  final value = row['channel']?.toString().trim();
  return value == null || value.isEmpty || value == '0' ? null : value;
}

String? wifiBand(Json row) {
  final mhz = num.tryParse(row['frequency_mhz']?.toString() ?? '');
  if (mhz == null) return null;
  if (mhz >= 2400 && mhz <= 2500) return '2.4 GHz';
  if (mhz >= 4900 && mhz < 5925) return '5 GHz';
  if (mhz >= 5925 && mhz <= 7125) return '6 GHz';
  return null;
}
