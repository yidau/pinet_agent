"""Single administrator-triggered nl80211 scan and Kismet scanreport submission."""

import argparse
from contextlib import closing
import errno
import json
import os
from pathlib import Path
import re
import signal
import socket
import sqlite3
import tempfile
import time
import uuid

from .kismet_adapter import KismetAdapter, KismetError


STATE = Path("/run/piagent-managed-scan/status.json")
MONITOR_RESERVATION = Path("/etc/piagent-wireless-monitor-port")
MONITOR_INTERFACE = "pn-wifi0"
MAX_APS = 128
MAX_AGE = 300
MAX_SAVED_POINTS = 4096


def empty_state(reason, status="DEGRADED"):
    return {"status": status, "reason": reason, "source_uuid": None, "access_points": [],
            "observed_at": None, "submitted_count": 0, "withheld_unknown_security": 0,
            "truncated": False, "in_progress": False}


def read_managed_scan(path=None):
    """Read only the current boot's bounded, atomically published result."""
    if path is None:
        path = STATE
    try:
        with path.open("rb") as source:
            data = source.read(256 * 1024 + 1)
        if len(data) > 256 * 1024:
            raise ValueError("oversized state")
        result = json.loads(data)
        if not isinstance(result, dict) or result.get("status") not in ("AVAILABLE", "DEGRADED", "ERROR"):
            raise ValueError("invalid state")
        if not isinstance(result.get("reason"), str):
            raise ValueError("invalid reason")
        if result["status"] == "AVAILABLE":
            uuid.UUID(result["source_uuid"])
            rows = result["access_points"]
            if not isinstance(rows, list) or len(rows) > MAX_APS or type(result["truncated"]) is not bool:
                raise ValueError("invalid observation list")
            for row in rows:
                if (not isinstance(row, dict) or not isinstance(row.get("mac"), str)
                        or row.get("id") != row["mac"] or "name" not in row or "channel" not in row):
                    raise ValueError("invalid AP observation")
        age = time.monotonic() - result.pop("written_monotonic")
        if result.get("in_progress") and not 0 <= age <= 30:
            return {**empty_state("The managed scan ended without a Kismet acknowledgement."),
                    "source_uuid": result.get("source_uuid")}
        if result["status"] == "AVAILABLE" and not 0 <= age <= MAX_AGE:
            return {**empty_state("The last managed scan expired. Request a new local scan."),
                    "source_uuid": result.get("source_uuid"), "observed_at": result.get("observed_at")}
        return result
    except FileNotFoundError:
        return empty_state("No recent operator-authorized managed scan is available.")
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RecursionError):
        return empty_state("Cannot read the managed scan reporter state.", "ERROR")


def publish(result):
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=STATE.parent, delete=False) as out:
        temp = Path(out.name)
        try:
            os.fchmod(out.fileno(), 0o640)
            json.dump({**result, "written_monotonic": time.monotonic()}, out, ensure_ascii=True)
            out.flush()
            os.replace(temp, STATE)
        finally:
            temp.unlink(missing_ok=True)


def record_managed_history(source_uuid, points):
    """Journal acknowledged scans even when no MCP client is reading the current status."""
    if not points:
        return
    path = STATE.with_name("observations.sqlite3")
    with closing(sqlite3.connect(path, timeout=1)) as db, db:
        db.execute("""CREATE TABLE IF NOT EXISTS samples (
            source_uuid TEXT, bssid TEXT, timestamp REAL, rssi_dbm REAL, channel TEXT,
            UNIQUE (source_uuid, bssid, timestamp))""")
        db.executemany("INSERT OR REPLACE INTO samples VALUES (?, ?, ?, ?, ?)", (
            (source_uuid, row["mac"], row["observed_at"], row["rssi_dbm"], row["channel"]) for row in points))
        db.execute("DELETE FROM samples WHERE rowid IN (SELECT rowid FROM samples ORDER BY rowid DESC LIMIT -1 OFFSET ?)",
                   (MAX_SAVED_POINTS,))
        first_seen = dict(db.execute("SELECT bssid, MIN(timestamp) FROM samples WHERE source_uuid=? GROUP BY bssid",
                                     (source_uuid,)))
    for row in points:
        row["first_seen"] = first_seen[row["mac"]]


def read_managed_history(source_uuid, bssid):
    return read_managed_histories(source_uuid, [bssid]).get(bssid, [])


def read_managed_histories(source_uuid, bssids):
    """Read bounded AP histories from a single consistent journal snapshot."""
    path = STATE.with_name("observations.sqlite3")
    if not source_uuid or not bssids:
        return {}
    result = {}
    try:
        with closing(sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True, timeout=1)) as db:
            db.execute("BEGIN")
            for bssid in bssids:
                rows = db.execute("""SELECT timestamp, rssi_dbm, channel FROM samples
                                     WHERE source_uuid=? AND bssid=? ORDER BY timestamp DESC LIMIT 64""",
                                  (source_uuid, bssid))
                result[bssid] = [{"timestamp": ts, "rssi_dbm": rssi, "channel": ch, "observation_source": "managed_scan"}
                                 for ts, rssi, ch in rows]
        return result
    except (OSError, sqlite3.Error):
        # Older helpers may have no journal. The service still has its measured session samples.
        return {}


def wifi_channel(freq):
    # IEEE channel numbers for the 2.4, 5 and 6 GHz bands.
    if freq == 2484:
        return 14
    if freq == 5935:
        return 2
    for lo, hi, base in ((2412, 2472, 2407), (4910, 4980, 4000),
                         (5005, 5895, 5000), (5955, 7115, 5950)):
        if lo <= freq <= hi and (freq - base) % 5 == 0:
            return (freq - base) // 5
    return None


def scan_security(elements, flags):
    rsn = elements.get("RSN")
    if isinstance(rsn, dict):
        suites = {"PSK": "PSK", "SAE": "SAE", "FT/SAE": "FT/SAE", "FT/PSK": "FT/PSK",
                  "IEEE 802.1X": "EAP", "OWE": "OWE"}
        auths = [suites[s] for s in rsn.get("auth_suites", []) if s in suites]
        pairs = rsn.get("pairwise_cipher", [])
        if isinstance(pairs, str):
            pairs = [pairs]
        ciphers = [c for c in pairs if c in ("CCMP", "GCMP", "TKIP")]
        tokens = "-".join(filter(None, ("RSN", "+".join(auths) or "UNKNOWN", "+".join(ciphers))))
        return f"[{tokens}][ESS]"
    if any(v.startswith(b"\x00\x50\xf2\x01") for v in elements.get("VENDOR", [])):
        return "[WPA-UNKNOWN][ESS]"
    if isinstance(flags, int) and not flags & 0x10:
        return "[ESS]"
    # The privacy bit alone is insufficient to identify WEP or the actual cipher.
    return None


def access_point(bss, now, scan_seconds):
    addr = bss.get_attr("NL80211_BSS_BSSID")
    if isinstance(addr, bytes):
        addr = addr.hex(":")
    if not isinstance(addr, str) or not re.fullmatch(r"(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}", addr):
        return None
    capability = bss.get_attr("NL80211_BSS_CAPABILITY") or {}
    flags = capability.get("VALUE")
    if not isinstance(flags, int) or not flags & 1 or flags & 2:
        return None  # Only infrastructure BSS entries are APs.
    age_ms = bss.get_attr("NL80211_BSS_SEEN_MS_AGO")
    if type(age_ms) is not int or not 0 <= age_ms <= 1000 * (scan_seconds + 1):
        return None  # An older kernel cache entry does not belong to this scan.
    elements = {**(bss.get_attr("NL80211_BSS_BEACON_IES") or {}),
                **(bss.get_attr("NL80211_BSS_INFORMATION_ELEMENTS") or {})}
    raw_ssid = elements.get("SSID")
    ssid = None
    if isinstance(raw_ssid, bytes) and raw_ssid.strip(b"\x00"):
        try:
            ssid = raw_ssid.decode("utf-8")
        except UnicodeDecodeError:
            pass  # The SSID octets have no known display encoding.
    freq = bss.get_attr("NL80211_BSS_FREQUENCY")
    if type(freq) is not int or freq <= 0:
        freq = None
    channel = elements.get("CHANNEL") or (elements.get("HT_OPERATION") or {}).get("PRIMARY_CHANNEL")
    if not channel and freq:
        channel = wifi_channel(freq)
    signal_mbm = (bss.get_attr("NL80211_BSS_SIGNAL_MBM") or {}).get("VALUE")
    rssi = signal_mbm / 100 if type(signal_mbm) is int and -50000 <= signal_mbm <= 0 else None
    caps = scan_security(elements, flags)
    return {"id": addr.lower(), "mac": addr.lower(), "name": ssid,
            "channel": str(channel) if channel else None, "frequency_mhz": freq,
            "rssi_dbm": rssi, "security": caps, "observed_at": round(now - age_ms / 1000, 3),
            "source": "Managed Scan", "kismet_reported": False}


def kismet_reports(points):
    reports = []
    for row in points:
        # Kismet treats missing encryption as open, and drops records without radio data.
        if row["security"] is None or all(row[k] is None for k in ("channel", "frequency_mhz", "rssi_dbm")):
            continue
        fields = {"timestamp": int(row["observed_at"]), "bssid": row["mac"], "ssid": row["name"],
                  "capabilities": row["security"], "channel": row["channel"], "signal": row["rssi_dbm"],
                  "freqkhz": row["frequency_mhz"] * 1000 if row["frequency_mhz"] else None}
        reports.append({k: v for k, v in fields.items() if v is not None})
    return reports


class ScanUnavailable(Exception):
    """The current radio or local authorization cannot perform this scan."""


def known_interface_radio(interface):
    kind = interface.get_attr("NL80211_ATTR_IFTYPE")
    phy = interface.get_attr("NL80211_ATTR_WIPHY")
    # The kernel's IFTYPE_UNSPECIFIED is zero. An unrecognized type may be
    # hosting an AP as far as the session preflight is concerned.
    return type(kind) is int and 1 <= kind <= 12 and type(phy) is int and 0 <= phy < 0xffffffff


def check_scan_radio(interfaces, ifindex, allow_shared_ap, require_known_topology):
    selected = next((i for i in interfaces if i.get_attr("NL80211_ATTR_IFINDEX") == ifindex), None)
    if selected is None or selected.get_attr("NL80211_ATTR_WIPHY") is None:
        raise ScanUnavailable("The selected interface has no identifiable Wi-Fi radio.")
    if require_known_topology and not all(known_interface_radio(i) for i in interfaces):
        raise ScanUnavailable("Cannot verify radio ownership of all wireless interfaces for continuous scanning.")
    phy = selected.get_attr("NL80211_ATTR_WIPHY")
    peers = [i for i in interfaces if i.get_attr("NL80211_ATTR_WIPHY") == phy]
    if any(i.get_attr("NL80211_ATTR_IFTYPE") == 6 or i.get_attr("NL80211_ATTR_IFNAME") == MONITOR_INTERFACE
           for i in peers):
        raise ScanUnavailable("This radio is reserved for passive monitoring.")
    ap_roles = (3, 4, 9) if require_known_topology else (3, 4)
    shares_ap = any(i.get_attr("NL80211_ATTR_IFTYPE") in ap_roles for i in peers)
    if shares_ap and not allow_shared_ap:
        raise ScanUnavailable("This radio hosts an AP. Shared-radio scanning needs explicit operator confirmation.")
    if selected.get_attr("NL80211_ATTR_IFTYPE") not in (2, 3):
        raise ScanUnavailable("The current interface mode does not support this managed scan.")
    return phy


def check_monitor_reservation(phy, reservation=MONITOR_RESERVATION, usb=Path("/sys/bus/usb/devices"),
                              wireless=Path("/sys/class/ieee80211")):
    """Protect the monitor's USB port even before udev has assigned its interface name."""
    try:
        port = reservation.read_text(encoding="ascii").strip()
    except FileNotFoundError:
        return
    except (OSError, UnicodeError) as exc:
        raise ScanUnavailable("Cannot read the passive monitor's USB reservation.") from exc
    if not re.fullmatch(r"[0-9]+-[0-9]+(?:\.[0-9]+)*", port) or type(phy) is not int or not 0 <= phy < 0xffffffff:
        raise ScanUnavailable("Cannot validate the passive monitor's USB reservation.")
    try:
        reserved = (usb / port).resolve(strict=True)
    except FileNotFoundError:
        return
    except (OSError, RuntimeError) as exc:
        raise ScanUnavailable("Cannot resolve the passive monitor's USB port.") from exc
    try:
        device = (wireless / f"phy{phy}" / "device").resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise ScanUnavailable("Cannot verify the scan interface's physical device.") from exc
    if reserved == device or reserved in device.parents:
        raise ScanUnavailable("This USB radio is assigned to passive monitoring.")


def collect(interface, allow_shared_ap, *, require_known_topology=False):
    try:
        from pyroute2 import IW
        from pyroute2.netlink.exceptions import NetlinkError
    except ImportError:
        raise ScanUnavailable("Install python3-pyroute2 for the system Python.") from None
    try:
        ifindex = socket.if_nametoindex(interface)
        with IW() as radio:
            phy = check_scan_radio(list(radio.list_dev()), ifindex, allow_shared_ap, require_known_topology)
            check_monitor_reservation(phy)
            start = time.monotonic()
            points = {}
            earlier = []
            truncated = False
            for msg in radio.scan(ifindex, ssids=[""]):
                bss = msg.get_attr("NL80211_ATTR_BSS")
                if bss is None:
                    continue
                row = access_point(bss, time.time(), time.monotonic() - start)
                if row is None:
                    continue
                if len(points) == MAX_APS and row["mac"] not in points:
                    truncated = True
                    continue
                previous = points.get(row["mac"])
                if previous is not None:
                    if previous["observed_at"] > row["observed_at"]:
                        previous, row = row, previous
                    if len(earlier) < MAX_APS:
                        earlier.append(previous)
                points[row["mac"]] = row
            return list(points.values()), earlier, truncated
    except (NetlinkError, OSError) as exc:
        code = abs(getattr(exc, "code", None) or getattr(exc, "errno", None) or 0)
        if code in (0, errno.EACCES, errno.EPERM, errno.EBUSY, errno.ENODEV,
                    errno.ENETDOWN, errno.EOPNOTSUPP, errno.EINVAL, getattr(errno, "ERFKILL", 132)):
            raise ScanUnavailable(f"Wireless scan unavailable ({exc}). Check interface, permissions and AP coexistence.") from exc
        raise


def run(mode):
    # Only the manually started unit can read scanreport credentials and write status.
    import fcntl
    with (STATE.parent / "scan.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("A managed scan is already in progress.") from None
        try:
            source_uuid = str(uuid.UUID(os.environ["PIAGENT_SCAN_UUID"]))
        except (ValueError, KeyError):
            publish(empty_state("The managed scan source UUID is not configured correctly.", "ERROR"))
            return 1
        if mode == "hold":
            publish({**empty_state("The operator suspended managed scanning to preserve radio coexistence."),
                     "source_uuid": source_uuid})
            return 0
        scan_id = os.environ.get("INVOCATION_ID", "") if mode == "monitoring" else uuid.uuid4().hex
        if not re.fullmatch("[0-9a-f]{32}", scan_id):
            raise SystemExit("Monitoring scan requires a systemd invocation ID.")
        result = {**empty_state("A local scan is in progress."), "in_progress": True, "source_uuid": source_uuid,
                  "scan_mode": mode, "scan_id": scan_id}
        publish(result)
        def interrupted(signum, frame):
            raise ScanUnavailable("Managed scan timed out or was stopped by the operator.")
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGALRM, interrupted)
        signal.alarm(22)
        try:
            interface = os.environ["PIAGENT_SCAN_INTERFACE"]
            adapter = KismetAdapter(os.environ["PIAGENT_SCAN_URL"], os.environ["PIAGENT_SCAN_KEY"])
            points, earlier, truncated = collect(interface, mode == "shared-ap", require_known_topology=mode == "monitoring")
            reports = kismet_reports(points)
            adapter.submit_scan_report(source_uuid, f"PiAgent Managed Scan ({interface})", reports)
            reported = {row["bssid"] for row in reports}
            for row in points:
                row["kismet_reported"] = row["mac"] in reported
            try:
                record_managed_history(source_uuid, [*earlier, *points])
            except sqlite3.Error:
                print("Managed scan history could not be saved; the current report is available.", flush=True)
            result.update(status="AVAILABLE", reason="", access_points=points,
                          observed_at=int(time.time()), truncated=truncated, submitted_count=len(reports),
                          withheld_unknown_security=sum(row["security"] is None for row in points))
        except ScanUnavailable as exc:
            result["reason"] = str(exc)
        except KismetError as exc:
            result.update(status="ERROR", reason=str(exc))
        except (KeyError, ValueError, OSError, RuntimeError) as exc:
            result.update(status="ERROR", reason=f"Managed scan failed ({type(exc).__name__}).")
        except Exception as exc:
            # Preserve a terminal error even if the netlink decoder rejected a BSS.
            result.update(status="ERROR", reason=f"Scan provider failed ({type(exc).__name__}).")
        finally:
            signal.alarm(0)
        result["in_progress"] = False
        publish(result)
        print(f"{result['status']} submitted={result['submitted_count']} {result['reason']}", flush=True)
        return 0 if result["status"] == "AVAILABLE" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("normal", "shared-ap", "hold", "monitoring"))
    raise SystemExit(run(parser.parse_args().mode))
