"""Translate current Kismet observations into PocketNet capabilities and results."""

import shutil
import subprocess
from collections import Counter
from datetime import datetime, timezone

from .capabilities import CapabilityStatus as State
from .kismet_adapter import PAGE_SIZE, KismetAdapter, KismetError


NO_SOURCE = "No supported wireless capture source is available."
NO_HISTORY = "No recorded dBm history is available in the current Wi-Fi device view."
NO_AP = "No access point has been recorded in the current Wi-Fi device view."
KISMET_TOOLS = frozenset({
    "get_kismet_status", "get_kismet_version", "get_kismet_datasources",
    "get_kismet_devices", "get_kismet_alerts", "get_kismet_capture_status",
})
DISCOVERY = frozenset({
    "scan_wireless_environment", "get_access_points", "get_ap_details",
    "get_wireless_clients", "get_wifi_channels", "get_signal_history",
})
WIRELESS = DISCOVERY | {"get_wireless_events"}


class WirelessError(Exception):
    def __init__(self, status: State, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code


def capture_info(sources):
    # The Linux Wi-Fi capture driver supplies monitor observations for the Pi.
    # A paused/broken source, a replay file or another PHY cannot satisfy this.
    active = sum(source["driver"] == "linuxwifi" and source["running"] and
                 not source["paused"] and not source["error"] for source in sources)
    return {"datasource_count": len(sources), "active_wifi_sources": active,
            "wireless_status": State.AVAILABLE if active else State.DEGRADED,
            "reason": "" if active else NO_SOURCE}


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


class WirelessService:
    tool_names = KISMET_TOOLS | WIRELESS

    def __init__(self, adapter: KismetAdapter | None = None):
        self.adapter = adapter if adapter is not None else KismetAdapter()

    def snapshot(self):
        states = dict.fromkeys(self.tool_names, (State.AVAILABLE, ""))
        summary = {"installed": None, "running": None, "version": None,
                   "datasource_count": None, "active_wifi_sources": None,
                   "wireless_status": State.ERROR, "reason": ""}
        try:
            summary.update(self.adapter.get_server_status())
        except KismetError as error:
            # The executable can still be installed when authentication or HTTP fails.
            summary["installed"], summary["running"] = local_process_state()
            summary["reason"] = str(error)
            if error.code in {"KISMET_CONFIGURATION", "KISMET_CONNECTION"}:
                states.update(dict.fromkeys(self.tool_names, (State.ERROR, str(error))))
                return states, summary
            states["get_kismet_status"] = states["get_kismet_version"] = (State.ERROR, str(error))

        try:
            self.adapter.get_devices()
        except KismetError as error:
            states["get_kismet_devices"] = State.ERROR, str(error)
        alerts = None
        try:
            alerts = self.adapter.get_alerts()
        except KismetError as error:
            states["get_kismet_alerts"] = State.ERROR, str(error)

        try:
            capture = capture_info(self.adapter.get_datasources())
            summary.update(capture)
        except KismetError as error:
            summary["reason"] = str(error)
            affected = WIRELESS | {"get_kismet_datasources", "get_kismet_capture_status"}
            states.update(dict.fromkeys(affected, (State.ERROR, str(error))))
            return states, summary
        if not capture["active_wifi_sources"]:
            states.update(dict.fromkeys(WIRELESS, (State.DEGRADED, NO_SOURCE)))
            return states, summary

        try:
            devices, _ = self.adapter.get_devices(wireless=True)
            if not any(device["samples"] for device in devices):
                states["get_signal_history"] = State.DEGRADED, NO_HISTORY
            if not any(device["type"] == "Wi-Fi AP" for device in devices):
                states["get_ap_details"] = State.DEGRADED, NO_AP
        except KismetError as error:
            summary.update(wireless_status=State.ERROR, reason=str(error))
            states.update(dict.fromkeys(DISCOVERY, (State.ERROR, str(error))))
        if alerts is None:
            states["get_wireless_events"] = states["get_kismet_alerts"]
        elif alerts:
            try:
                self.adapter.get_wifi_phy_id()
            except KismetError as error:
                states["get_wireless_events"] = State.ERROR, str(error)
        return states, summary

    def call(self, name: str, *, ap_id: str | None = None):
        try:
            data = self._read(name, ap_id)
        except KismetError as error:
            raise WirelessError(State.ERROR, error.code, str(error)) from error
        return {**data, "source": "kismet", "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")}

    def _read(self, name, ap_id):
        if name in ("get_kismet_status", "get_kismet_version"):
            status = self.adapter.get_server_status()
            return status if name == "get_kismet_status" else {"version": status["version"]}
        if name == "get_kismet_devices":
            devices, total = self.adapter.get_devices()
            return {"devices": [public_device(device) for device in devices],
                    "total": total, "truncated": total > len(devices)}
        if name == "get_kismet_alerts":
            alerts = self.adapter.get_alerts()
            return {"alerts": [public_alert(alert) for alert in alerts[:PAGE_SIZE]],
                    "total": len(alerts), "truncated": len(alerts) > PAGE_SIZE}
        sources = self.adapter.get_datasources()
        capture = capture_info(sources)
        if name == "get_kismet_datasources":
            return {"datasources": sources, "datasource_count": len(sources)}
        if name == "get_kismet_capture_status":
            return capture
        if name not in WIRELESS:
            raise WirelessError(State.UNAVAILABLE, "CAPABILITY_UNAVAILABLE", "This capability is not implemented.")
        if not capture["active_wifi_sources"]:
            raise WirelessError(State.DEGRADED, "CAPABILITY_UNAVAILABLE", NO_SOURCE)
        if name == "get_wireless_events":
            alerts = self.adapter.get_alerts()
            if alerts:
                phy = self.adapter.get_wifi_phy_id()
                alerts = [alert for alert in alerts if alert["phy_id"] == phy]
            return {"events": [public_alert(alert) for alert in alerts[:PAGE_SIZE]],
                    "total": len(alerts), "truncated": len(alerts) > PAGE_SIZE}

        devices, total = self.adapter.get_devices(wireless=True)
        scope = {"sampled_devices": len(devices), "total_wifi_devices": total, "truncated": total > len(devices)}
        aps = [public_device(device) for device in devices if device["type"] == "Wi-Fi AP"]
        clients = [public_device(device) for device in devices if device["type"] == "Wi-Fi Client"]
        counts = Counter(device["channel"] for device in devices if device["channel"] not in ("", "0", None))
        channels = [{"channel": channel, "device_count": count} for channel, count in counts.most_common()]
        if name == "scan_wireless_environment":
            return {**scope, "access_point_count": len(aps), "client_count": len(clients), "channels": channels}
        if name == "get_access_points":
            return {**scope, "access_points": aps}
        if name == "get_wireless_clients":
            return {**scope, "clients": clients}
        if name == "get_wifi_channels":
            return {**scope, "channels": channels}
        if name == "get_signal_history":
            history = [{"id": d["id"], "name": d["name"], "samples": d["samples"]} for d in devices if d["samples"]]
            if not history:
                raise WirelessError(State.DEGRADED, "CAPABILITY_UNAVAILABLE", NO_HISTORY)
            return {**scope, "history": history}
        if not aps:
            raise WirelessError(State.DEGRADED, "CAPABILITY_UNAVAILABLE", NO_AP)
        for ap in aps:
            if ap["id"] == ap_id:
                return {"access_point": ap}
        raise WirelessError(State.ERROR, "AP_NOT_IN_VIEW", "The selected AP is absent from the current device view.")
