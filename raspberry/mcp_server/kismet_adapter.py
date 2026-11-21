"""Bounded, read-only requests to the Kismet instance on this host."""

import http.client
import ipaddress
import json
import math
import os
import re
from urllib.parse import urlencode, urlsplit


PAGE_SIZE = 32
MAX_RESPONSE_BYTES = 1024 * 1024
DEVICE_FIELDS = [
    "kismet.device.base.key", "kismet.device.base.name", "kismet.device.base.macaddr",
    "kismet.device.base.type", "kismet.device.base.phyname", "kismet.device.base.channel",
    "kismet.device.base.signal",
]


class KismetError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def malformed():
    return KismetError("KISMET_INVALID_RESPONSE", "Kismet returned an unexpected response format.")


def records(value):
    if not isinstance(value, list) or any(not isinstance(row, dict) for row in value):
        raise malformed()
    return value


def string_field(row, key):
    value = row.get(key)
    if not isinstance(value, str) or not value:
        raise malformed()
    return value


def optional_text(row, key):
    value = row.get(key)
    if value is not None and not isinstance(value, str):
        raise malformed()
    return value


def flag(row, key):
    value = row.get(key)
    if type(value) not in (bool, int) or value not in (0, 1):
        raise malformed()
    return bool(value)


def signal_history(signal):
    if signal.get("kismet.common.signal.type") != "dbm":
        return []
    # 2026 uses the explicit peak field; older releases called it signal_rrd.
    rrd = signal.get("kismet.common.signal.max_signal_rrd", signal.get("kismet.common.signal.signal_rrd"))
    if not rrd:
        return []
    if not isinstance(rrd, dict):
        raise malformed()
    values = rrd.get("kismet.common.rrd.minute_vec")
    end = rrd.get("kismet.common.rrd.serial_time")
    if not isinstance(values, list) or len(values) != 60 or type(end) is not int:
        raise malformed()
    samples = []
    for timestamp in range(end - 59, end + 1):
        value = values[timestamp % 60]
        if type(value) not in (int, float) or not math.isfinite(value):
            raise malformed()
        if value != rrd.get("kismet.common.rrd.blank_val") and value < 0:
            samples.append({"timestamp": timestamp, "rssi_dbm": value})
    return samples


class KismetAdapter:
    def __init__(self, base_url: str | None = None, api_key: str | None = None):
        self._url = base_url if base_url is not None else os.environ.get("PIAGENT_KISMET_URL", "")
        self._key = api_key if api_key is not None else os.environ.get("PIAGENT_KISMET_API_KEY", "")

    def _request(self, path: str, form: dict | None = None):
        # http.client neither follows redirects nor uses system proxy settings.
        try:
            url = urlsplit(self._url)
            host = url.hostname
            port = url.port
            if (url.scheme not in ("http", "https") or not host or not port
                    or not ipaddress.ip_address(host).is_loopback or "@" in url.netloc
                    or url.path not in ("", "/") or url.query or url.fragment):
                raise ValueError()
        except ValueError:
            raise KismetError("KISMET_CONFIGURATION", "Set a loopback Kismet URL with its configured port.") from None
        if not re.fullmatch(r"[A-Za-z0-9._~+/=-]+", self._key):
            raise KismetError("KISMET_CONFIGURATION", "The local read-only Kismet API key is missing or invalid.")
        headers = {"Cookie": "KISMET=" + self._key, "Accept": "application/json"}
        body = None
        if form is not None:
            body = urlencode(form)
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        connection_cls = http.client.HTTPSConnection if url.scheme == "https" else http.client.HTTPConnection
        connection = connection_cls(host, port, timeout=1.5)
        try:
            connection.request("GET" if form is None else "POST", path, body, headers)
            response = connection.getresponse()
            if response.status in (401, 403):
                raise KismetError("KISMET_AUTHENTICATION", "Kismet refused the local API credentials.")
            if response.status != 200:
                raise KismetError("KISMET_HTTP_ERROR", f"Kismet returned HTTP {response.status}.")
            data = response.read(MAX_RESPONSE_BYTES + 1)
            if len(data) > MAX_RESPONSE_BYTES:
                raise KismetError("KISMET_RESPONSE_LIMIT", "The Kismet response exceeded the size limit.")
            return json.loads(data)
        except (TimeoutError, http.client.HTTPException, OSError):
            raise KismetError("KISMET_CONNECTION", "The local Kismet API could not be reached.") from None
        except (ValueError, UnicodeError, RecursionError):
            raise malformed() from None
        finally:
            connection.close()

    def get_server_status(self):
        row = self._request("/system/status.json")
        if not isinstance(row, dict):
            raise malformed()
        return {"installed": True, "running": True, "version": string_field(row, "kismet.system.version")}

    def get_datasources(self):
        rows = records(self._request("/datasource/all_sources.json"))
        sources = []
        for row in rows:
            driver = row.get("kismet.datasource.type_driver")
            if not isinstance(driver, dict):
                raise malformed()
            sources.append({
                "name": string_field(row, "kismet.datasource.name"),
                "uuid": string_field(row, "kismet.datasource.uuid"),
                "driver": string_field(driver, "kismet.datasource.driver.type"),
                "interface": optional_text(row, "kismet.datasource.interface"),
                "running": flag(row, "kismet.datasource.running"),
                "paused": flag(row, "kismet.datasource.paused"),
                "error": flag(row, "kismet.datasource.error"),
            })
        return sources

    def get_devices(self, *, wireless=False):
        view = "phy-IEEE802.11" if wireless else "all"
        result = self._request(f"/devices/views/{view}/devices.json", {
            "json": json.dumps({"fields": DEVICE_FIELDS, "datatable": True}),
            "start": 0, "length": PAGE_SIZE, "draw": 1,
        })
        if not isinstance(result, dict):
            raise malformed()
        rows = records(result.get("data"))
        total = result.get("recordsFiltered")
        if len(rows) > PAGE_SIZE or type(total) is not int or total < len(rows):
            raise malformed()
        devices = []
        for row in rows:
            signal = row.get("kismet.device.base.signal", {})
            if not isinstance(signal, dict):
                raise malformed()
            last = signal.get("kismet.common.signal.last_signal")
            if last is not None and (type(last) not in (float, int) or not math.isfinite(last)):
                raise malformed()
            dbm = signal.get("kismet.common.signal.type") == "dbm"
            devices.append({
                "id": string_field(row, "kismet.device.base.key"),
                "mac": string_field(row, "kismet.device.base.macaddr"),
                "type": string_field(row, "kismet.device.base.type"),
                "phy": string_field(row, "kismet.device.base.phyname"),
                "name": optional_text(row, "kismet.device.base.name"),
                "channel": optional_text(row, "kismet.device.base.channel"),
                "rssi_dbm": last if dbm and last is not None and last < 0 else None,
                "samples": signal_history(signal) if wireless else [],
            })
        return devices, total

    def get_alerts(self):
        rows = records(self._request("/alerts/all_alerts.json"))
        alerts = []
        for row in rows:
            timestamp = row.get("kismet.alert.timestamp")
            if type(timestamp) not in (float, int) or not math.isfinite(timestamp):
                raise malformed()
            phy_id = row.get("kismet.alert.phy_id")
            if type(phy_id) is not int:
                raise malformed()
            alerts.append({"timestamp": timestamp, "type": string_field(row, "kismet.alert.header"),
                           "message": string_field(row, "kismet.alert.text")[:512],
                           "phy_id": phy_id})
        alerts.sort(key=lambda item: item["timestamp"], reverse=True)
        return alerts

    def get_wifi_phy_id(self):
        rows = records(self._request("/phy/all_phys.json"))
        for row in rows:
            if row.get("kismet.phy.phy_name") == "IEEE802.11" and type(row.get("kismet.phy.phy_id")) is int:
                return row["kismet.phy.phy_id"]
        raise KismetError("KISMET_PHY_UNKNOWN", "Kismet did not report the Wi-Fi PHY identifier.")
