"""Group current Wi-Fi evidence by BSSID and keep a bounded window of measured samples."""

from collections import OrderedDict, defaultdict
import math
import re
from threading import Lock


MAX_HISTORY = 64
MAX_HISTORY_BSSIDS = 512


def canonical_bssid(value):
    if not isinstance(value, str):
        return None
    address = value.lower().replace("-", ":")
    return address if re.fullmatch(r"(?:[a-f0-9]{2}:){5}[a-f0-9]{2}", address) else None


def timestamp(value):
    return value if type(value) in (int, float) and math.isfinite(value) and value > 0 else None


def known_channel(row):
    value = row.get("channel")
    return str(value) if type(value) in (int, str) and value not in (0, "0", "") else None


def advertised_name(row):
    name = row.get("ssid", row.get("name"))
    if not isinstance(name, str) or not name.strip("\0"):
        return None
    if "ssid" not in row and canonical_bssid(name) == canonical_bssid(row["mac"]):
        return None
    return name


def measurement(row):
    when = timestamp(row.get("observed_at")) or timestamp(row.get("last_seen"))
    if when is not None:
        return {"timestamp": when, "channel": known_channel(row), "rssi_dbm": row.get("rssi_dbm"),
                "observation_source": row["observation_source"]}


def merge_samples(samples):
    distinct = {}
    for point in samples:
        key = (point["timestamp"], point["observation_source"])
        # A measured row is more specific than a Kismet one-second peak at the same instant.
        if point.get("sample_kind") != "rrd_peak" or key not in distinct:
            distinct[key] = point
    return [distinct[key] for key in sorted(distinct)[-MAX_HISTORY:]]


class ApObservations:
    def __init__(self):
        self._recent = OrderedDict()
        self._lock = Lock()

    def current(self, rows):
        by_address = defaultdict(list)
        for row in rows:
            address = canonical_bssid(row.get("mac"))
            if address is not None:
                by_address[address].append(row)

        aps = []
        aliases = {}
        related_ids = {}
        with self._lock:
            for address, reports in by_address.items():
                # Ties prefer the scan row, which has explicit radio / security fields.
                reports.sort(key=lambda r: (timestamp(r.get("observed_at")) or timestamp(r.get("last_seen")) or 0,
                                            r["observation_source"] == "managed_scan"))
                current = reports[-1]
                samples = []
                times = []
                relations = set()
                for row in reports:
                    aliases[row["id"]] = address
                    relations.update(value for value in row.get("related_device_ids", ()) if isinstance(value, str))
                    if row["observation_source"] == "monitor_mode":
                        for point in row.get("samples", ()):
                            if timestamp(point.get("timestamp")) is not None:
                                samples.append({**point, "channel": None, "observation_source": "monitor_mode",
                                                "sample_kind": "rrd_peak"})
                    point = measurement(row)
                    if point:
                        samples.append(point)
                    first = timestamp(row.get("first_seen"))
                    if first is not None:
                        times.append(first)

                old_first, previous = self._recent.pop(address, (None, []))
                if old_first is not None:
                    times.append(old_first)
                times.extend(point["timestamp"] for point in samples)
                first_seen = min(times, default=None)
                history = merge_samples([*previous, *samples])
                self._recent[address] = first_seen, history
                ap = {k: v for k, v in current.items() if k not in ("samples", "related_device_ids", "live_sighting")}
                ssid = next((name for r in reversed(reports) if (name := advertised_name(r)) is not None), None)
                # Multi-source Kismet views can supply a recent signal without an attributable
                # SSID/channel. Fill descriptive fields only from reports for this same BSSID.
                compatible = [r for r in reversed(reports) if advertised_name(r) in (None, ssid)]
                radio = next((r for r in compatible if known_channel(r) or r.get("frequency_mhz")), current)
                security = next((r["security"] for r in compatible if r.get("security")), None)
                signal = next((r for r in compatible if type(r.get("rssi_dbm")) in (int, float)
                               and math.isfinite(r["rssi_dbm"])), {})
                ap.update(bssid=address, ssid=ssid, channel=known_channel(radio),
                          frequency_mhz=radio.get("frequency_mhz"), security=security,
                          rssi_dbm=signal.get("rssi_dbm"),
                          rssi_observed_at=timestamp(signal.get("observed_at")) or timestamp(signal.get("last_seen")),
                          first_seen=first_seen,
                          last_seen=timestamp(ap.get("observed_at")) or timestamp(ap.get("last_seen")),
                          observation_sources=sorted({r["observation_source"] for r in reports}),
                          kismet_device_ids=sorted({r["id"] for r in reports if r["observation_source"] == "monitor_mode"}))
                if ap.get("name") is None:
                    ap["name"] = ssid
                related_ids[address] = relations
                aps.append(ap)
            while len(self._recent) > MAX_HISTORY_BSSIDS:
                self._recent.popitem(last=False)
        for ap in aps:
            linked = {aliases.get(value) or canonical_bssid(value) for value in related_ids[ap["bssid"]]}
            ap["related_bssids"] = sorted((linked & by_address.keys()) - {ap["bssid"]})
        return aps, aliases

    def history(self, address, saved):
        with self._lock:
            _, recent = self._recent.get(address, (None, []))
            return merge_samples([*saved, *recent])


def network_summary(aps):
    groups = defaultdict(list)
    for ap in aps:
        # A hidden or undecodable SSID has no shared network identity.
        key = (ap["ssid"], ap["bssid"] if ap["ssid"] is None else None)
        groups[key].append(ap)
    networks = []
    all_channels = set()
    for (ssid, _), rows in groups.items():
        channels = {channel for row in rows if (channel := known_channel(row)) is not None}
        all_channels.update(channels)
        signals = [row["rssi_dbm"] for row in rows if type(row.get("rssi_dbm")) in (int, float)
                   and math.isfinite(row["rssi_dbm"])]
        networks.append({
            "ssid": ssid, "bssids": sorted(row["bssid"] for row in rows),
            "bssid_count": len(rows), "channel_count": len(channels),
            "security_modes": sorted({row["security"] for row in rows if isinstance(row.get("security"), str)
                                      and row["security"]}),
            "strongest_rssi_dbm": max(signals, default=None), "weakest_rssi_dbm": min(signals, default=None),
            "last_seen": max((row["last_seen"] for row in rows if row["last_seen"] is not None), default=None),
        })
    return {"networks": networks, "network_count": len(networks),
            "bssid_count": len(aps), "channel_count": len(all_channels)}
