"""Translate Kismet sources and recent managed scans into PocketNet observations."""

import shutil
import subprocess
from collections import Counter
from datetime import datetime, timezone

from .capabilities import CapabilityStatus as State
from .file_sources import SourceError, SourceService
from .kismet_adapter import PAGE_SIZE, KismetAdapter, KismetError
from .managed_scan import read_managed_scan


NO_SOURCE = "No active monitor source or recent managed scan is available."
NO_MONITOR = "A running Linux Wi-Fi monitor source is required for this observation."
KISMET_TOOLS = {
    "get_kismet_status", "get_kismet_version", "get_kismet_datasources", "get_kismet_datasource_status",
    "get_kismet_devices", "get_kismet_alerts", "get_kismet_capture_status",
}
AP_TOOLS = {"scan_wireless_environment", "get_access_points", "get_ap_details", "get_wifi_channels"}
MONITOR_TOOLS = {"get_wireless_clients", "get_signal_history", "get_wireless_events"}


class WirelessError(Exception):
    def __init__(self, status: State, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code


def public_device(device):
    return {key: value for key, value in device.items() if key != "samples"}


def public_alert(alert):
    return {key: value for key, value in alert.items() if key != "phy_id"}


def local_process_state():
    installed = shutil.which("kismet") is not None
    try:
        result = subprocess.run(
            ["systemctl", "show", "piagent-kismet.service", "-p", "LoadState", "-p", "ActiveState"],
            capture_output=True, text=True, timeout=1, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return installed, None if installed else False
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if result.returncode == 0 and fields.get("LoadState") == "loaded":
        state = fields.get("ActiveState")
        if state == "active":
            return True, True
        if state in ("inactive", "failed"):
            return installed, False
    return installed, None if installed else False


def feature(status, reason=""):
    return {"status": status, "reason": reason}


class WifiView:
    """A bounded view of APs and clients with explicit observation provenance."""

    def __init__(self, adapter, sources, scan):
        managed = feature(scan["status"], scan["reason"])
        if managed["status"] == State.AVAILABLE and not any(
            s["uuid"].lower() == str(scan["source_uuid"]).lower() and s["driver"] == "virtual" for s in sources
        ):
            managed = feature(State.DEGRADED, "Kismet no longer reports the UUID of the last managed scan.")

        # File replay can populate the global PHY view while a real source is online.
        # Only query the device views belonging to currently running monitor sources.
        monitors = [s for s in sources if s["driver"] == "linuxwifi" and s["running"]
                    and not s["paused"] and not s["error"]]
        monitor = feature(State.DEGRADED, NO_MONITOR)
        monitor_rows = {}
        truncated = False
        if monitors:
            try:
                for source in monitors[:4]:
                    devices, total = adapter.get_source_devices(source["uuid"], phy="IEEE802.11")
                    truncated |= total > len(devices)
                    for row in devices:
                        if row["phy"] == "IEEE802.11":
                            monitor_rows[row["id"]] = {**row, "observation_source": "monitor_mode"}
                truncated |= len(monitors) > 4
                monitor = feature(State.AVAILABLE)
            except KismetError as error:
                monitor_rows.clear()
                monitor = feature(State.ERROR, str(error))
        self.features = {"managed_scan": managed, "monitor_mode": monitor}
        self.monitor = monitor
        self.monitors = len(monitors)
        self.managed = managed["status"] == State.AVAILABLE
        self.has_replay_source = any(s["driver"] in {"pcapfile", "kismetdb"} for s in sources)
        if self.managed or monitor["status"] == State.AVAILABLE:
            self.availability = feature(State.AVAILABLE)
        elif State.ERROR in (managed["status"], monitor["status"]):
            self.availability = monitor if monitor["status"] == State.ERROR else managed
        else:
            self.availability = feature(State.DEGRADED, NO_SOURCE + " " + managed["reason"])

        self.devices = list(monitor_rows.values())
        aps = {row["mac"].lower(): public_device(row) for row in self.devices if row["type"] == "Wi-Fi AP"}
        if self.managed:
            for record in scan["access_points"]:
                key = record["mac"].lower()
                entry = dict(record, observation_source="managed_scan", bssid=record["mac"], ssid=record["name"])
                if key in aps:
                    entry["observation_sources"] = ["managed_scan", "monitor_mode"]
                aps[key] = entry
            truncated |= scan["truncated"]
        self.aps = list(aps.values())
        self.clients = [public_device(row) for row in self.devices if row["type"] == "Wi-Fi Client"]
        self.history = [{"id": row["id"], "name": row["name"], "samples": row["samples"],
                         "observation_source": "monitor_mode"} for row in self.devices if row["samples"]]
        devices_seen = {d["mac"].lower() for d in self.devices} | set(aps)
        origin = "kismet" if not self.managed else (
            "managed_scan+kismet" if self.devices else "managed_scan")
        self.scope = {"sampled_devices": len(devices_seen), "total_wifi_devices": None if truncated else len(devices_seen),
                      "truncated": truncated, "source": origin}

    def tool_states(self):
        states = {name: (self.availability["status"], self.availability["reason"]) for name in AP_TOOLS}
        states.update({name: (self.monitor["status"], self.monitor["reason"]) for name in MONITOR_TOOLS})
        if self.availability["status"] == State.AVAILABLE and not self.aps:
            states["get_ap_details"] = State.DEGRADED, "No AP is present in the current observation."
        if self.monitor["status"] == State.AVAILABLE and not self.history:
            states["get_signal_history"] = State.DEGRADED, "No measured dBm history is available."
        if self.monitor["status"] == State.AVAILABLE and self.has_replay_source:
            states["get_wireless_events"] = State.DEGRADED, (
                "Kismet's Wi-Fi alert history may include offline replay. Use get_kismet_alerts for recorded events.")
        return states

    def read(self, name, ap_id):
        if name == "get_access_points":
            return {**self.scope, "access_points": self.aps}
        if name == "get_ap_details":
            for row in self.aps:
                if row["id"] == ap_id:
                    return {"access_point": row, "source": row["observation_source"]}
            raise WirelessError(State.ERROR, "AP_NOT_IN_VIEW", "The selected AP is absent from the current view.")
        if name == "get_wireless_clients":
            return {**self.scope, "clients": self.clients}
        if name == "get_signal_history":
            return {**self.scope, "history": self.history}
        counts = Counter(str(d["channel"]) for d in [*self.aps, *self.clients] if d["channel"] not in (None, "", "0", 0))
        result = {**self.scope, "channels": [{"channel": ch, "device_count": count} for ch, count in counts.most_common()]}
        if name == "scan_wireless_environment":
            result.update(access_point_count=len(self.aps), client_count=(
                len(self.clients) if self.monitor["status"] == State.AVAILABLE else None))
        return result


class WirelessService:
    tool_names = KISMET_TOOLS | AP_TOOLS | MONITOR_TOOLS | SourceService.tool_names

    def __init__(self, adapter: KismetAdapter | None = None, *, scan_reader=read_managed_scan, source_service=None):
        self.adapter = adapter if adapter is not None else KismetAdapter()
        self.scan_reader = scan_reader
        self.source_service = source_service if source_service is not None else SourceService(self.adapter)

    def _source_summary(self, sources, error_reason=""):
        states, extra = self.source_service.capabilities(sources)
        if sources is None:
            states.update(dict.fromkeys(AP_TOOLS | MONITOR_TOOLS, (State.ERROR, error_reason)))
            wifi_features = {key: feature(State.ERROR, error_reason) for key in ("managed_scan", "monitor_mode")}
            active_count = None
            wifi_state = feature(State.ERROR, error_reason)
        else:
            wifi = WifiView(self.adapter, sources, self.scan_reader())
            states.update(wifi.tool_states())
            wifi_features = wifi.features
            active_count = wifi.monitors + int(wifi.managed)
            wifi_state = wifi.availability
        source_states = {**wifi_features, "bluetooth_scan": extra["bluetooth_scanning"], "pcap_replay": extra["pcap_replay"]}
        return states, {"source_states": source_states, "datasource_count": None if sources is None else len(sources),
                        "active_wifi_sources": active_count, "wireless_status": wifi_state["status"],
                        "reason": wifi_state["reason"]}

    def snapshot(self):
        states = dict.fromkeys(KISMET_TOOLS, (State.AVAILABLE, ""))
        try:
            summary = dict(self.adapter.get_server_status())
        except KismetError as error:
            installed, running = local_process_state()
            summary = {"installed": installed, "running": running, "version": None}
            states["get_kismet_status"] = states["get_kismet_version"] = State.ERROR, str(error)
            if error.code in {"KISMET_CONFIGURATION", "KISMET_CONNECTION"}:
                states.update(dict.fromkeys(KISMET_TOOLS, (State.ERROR, str(error))))
                dependencies, details = self._source_summary(None, str(error))
                return {**states, **dependencies}, {**summary, **details}
        for name, collect in (("get_kismet_devices", self.adapter.get_devices), ("get_kismet_alerts", self.adapter.get_alerts)):
            try:
                collect()
            except KismetError as error:
                states[name] = State.ERROR, str(error)
        try:
            dependencies, details = self._source_summary(self.adapter.get_datasources())
        except KismetError as error:
            affected = {"get_kismet_datasources", "get_kismet_capture_status", "get_kismet_datasource_status"}
            states.update(dict.fromkeys(affected, (State.ERROR, str(error))))
            dependencies, details = self._source_summary(None, str(error))
        states.update(dependencies)
        if states["get_wireless_events"][0] == State.AVAILABLE and states["get_kismet_alerts"][0] == State.ERROR:
            states["get_wireless_events"] = states["get_kismet_alerts"]
        return states, {**summary, **details}

    def call(self, name, **arguments):
        try:
            data = self._read(name, arguments)
        except SourceError as error:
            raise WirelessError(error.status, error.code, str(error)) from error
        except KismetError as error:
            raise WirelessError(State.ERROR, error.code, str(error)) from error
        return {"source": "kismet", **data, "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")}

    def _read(self, name, arguments):
        if name in ("get_kismet_status", "get_kismet_version"):
            status = self.adapter.get_server_status()
            return status if name == "get_kismet_status" else {"version": status["version"]}
        if name == "get_kismet_devices":
            devices, total = self.adapter.get_devices()
            return {"devices": [public_device(device) for device in devices], "scope": "all_recorded_sources",
                    "total": total, "truncated": total > len(devices)}
        if name == "get_kismet_alerts":
            alerts = self.adapter.get_alerts()
            return {"alerts": [public_alert(alert) for alert in alerts[:PAGE_SIZE]],
                    "total": len(alerts), "truncated": len(alerts) > PAGE_SIZE}
        if name in {"get_capture_metadata", "list_captures"}:
            return self.source_service.call(name, None, **arguments)
        if name in self.source_service.tool_names:
            try:
                sources = self.adapter.get_datasources()
            except KismetError:
                sources = None
            return self.source_service.call(name, sources, **arguments)
        sources = self.adapter.get_datasources()
        if name == "get_kismet_datasources":
            return {"datasources": sources, "datasource_count": len(sources)}
        if name in ("get_kismet_capture_status", "get_kismet_datasource_status"):
            _, summary = self._source_summary(sources)
            return summary
        if name not in AP_TOOLS | MONITOR_TOOLS:
            raise WirelessError(State.UNAVAILABLE, "CAPABILITY_UNAVAILABLE", "This capability is not implemented.")
        wifi = WifiView(self.adapter, sources, self.scan_reader())
        status, reason = wifi.tool_states()[name]
        if status != State.AVAILABLE:
            raise WirelessError(status, "CAPABILITY_UNAVAILABLE", reason)
        if name == "get_wireless_events":
            alerts = self.adapter.get_alerts()
            if alerts:
                phy = self.adapter.get_wifi_phy_id()
                alerts = [alert for alert in alerts if alert["phy_id"] == phy]
            return {"events": [public_alert(alert) for alert in alerts[:PAGE_SIZE]], "scope": "recorded_wifi_alerts",
                    "total": len(alerts), "truncated": len(alerts) > PAGE_SIZE}
        return wifi.read(name, arguments.get("ap_id"))
