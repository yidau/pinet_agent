"""Associate one operator-selected USB radio with the local Kismet instance."""

from dataclasses import dataclass
import json
import logging
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
from threading import Event
import time
from uuid import UUID

from .kismet_adapter import KismetAdapter, KismetError, records


SOURCE_NAME = "PiAgent USB monitor"
MONITOR_INTERFACE = "pn-wifi0"
MONITOR_VIF = "pn-wifi0mon"
HOSTAPD = Path("/etc/hostapd/piagent.conf")
NET = Path("/sys/class/net")
POLL_SECONDS = 5
RETRY_SECONDS = 20
LOG = logging.getLogger(__name__)


class Unavailable(Exception):
    pass


@dataclass(frozen=True)
class MonitorConfig:
    vendor: str
    product: str
    port: str
    driver: str
    datasource_uuid: str
    kismet_port: int

    def __post_init__(self):
        for value, constraint in ((self.vendor, r"[a-f0-9]{4}"), (self.product, r"[a-f0-9]{4}"),
                                  (self.port, r"[0-9]+-[0-9]+(?:\.[0-9]+)*"),
                                  (self.driver, r"[A-Za-z0-9_-]{1,40}")):
            if not isinstance(value, str) or not re.fullmatch(constraint, value, re.ASCII):
                raise ValueError("Invalid wireless identity configuration.")
        if not isinstance(self.datasource_uuid, str) or str(UUID(self.datasource_uuid)) != self.datasource_uuid:
            raise ValueError("Invalid datasource UUID.")
        if type(self.kismet_port) is not int or not 1024 <= self.kismet_port <= 65535:
            raise ValueError("Invalid Kismet port.")


@dataclass(frozen=True)
class UsbRadio:
    phy: Path
    port: str
    vendor: str
    product: str
    driver: str
    ifindex: int


def usb_radio(interface):
    phy = (interface / "phy80211").resolve(strict=True)
    device = (phy / "device").resolve(strict=True)
    driver = (device / "driver").resolve(strict=True).name
    for ancestor in (device, *device.parents):
        if (ancestor / "idVendor").is_file() and (ancestor / "idProduct").is_file():
            return UsbRadio(phy, ancestor.name, (ancestor / "idVendor").read_text().strip().lower(),
                            (ancestor / "idProduct").read_text().strip().lower(), driver,
                            int((interface / "ifindex").read_text()))
    raise Unavailable("monitor_not_usb")


def matches_config(radio, config):
    return (radio.vendor, radio.product, radio.port, radio.driver) == (
        config.vendor, config.product, config.port, config.driver)


def iw(*args):
    return subprocess.check_output(["/usr/sbin/iw", *args], timeout=3, stderr=subprocess.DEVNULL,
                                   encoding="ascii", errors="replace")


def select_radio(config, net=NET, hostapd=HOSTAPD, query=iw):
    try:
        names = re.findall(r"(?m)^[ \t]*interface[ \t]*=[ \t]*([A-Za-z0-9_-][A-Za-z0-9_.-]{0,14})[ \t]*$",
                           hostapd.read_text())
        if len(names) != 1:
            raise ValueError()
        hotspot = (net / names[0] / "phy80211").resolve(strict=True)
    except (OSError, ValueError, RuntimeError) as exc:
        raise Unavailable("management_radio_unknown") from exc

    try:
        candidate = usb_radio(net / MONITOR_INTERFACE)
    except FileNotFoundError as exc:
        raise Unavailable("usb_monitor_missing") from exc
    except (OSError, ValueError, RuntimeError) as exc:
        raise Unavailable("monitor_identity_unknown") from exc
    if candidate.phy == hotspot:
        raise Unavailable("monitor_shares_hotspot")
    if not matches_config(candidate, config):
        raise Unavailable("monitor_identity_mismatch")
    try:
        virtual = net / MONITOR_VIF
        if virtual.exists() and (virtual / "phy80211").resolve(strict=True) != candidate.phy:
            raise Unavailable("monitor_vif_conflict")
        interfaces = query("dev")
        phy_no = candidate.phy.name.removeprefix("phy")
        phy_blocks = dict(re.findall(r"(?ms)^phy#(\d+)[ \t]*\n(.*?)(?=^phy#|\Z)", interfaces))
        if not phy_no.isascii() or not phy_no.isdecimal() or phy_no not in phy_blocks:
            raise Unavailable("monitor_identity_unknown")
        if re.search(r"(?m)^\s*type (?:AP(?:/VLAN)?|P2P-GO)\s*$", phy_blocks[phy_no]):
            raise Unavailable("monitor_radio_in_use")
        modes = re.search(r"(?m)^[ \t]*Supported interface modes:[ \t]*\n((?:[ \t]*\* [^\n]+\n)+)",
                          query("phy", candidate.phy.name, "info"))
        if modes is None or not re.search(r"(?m)^\s*\* monitor\s*$", modes[1]):
            raise Unavailable("monitor_mode_unavailable")
    except (OSError, subprocess.SubprocessError) as exc:
        raise Unavailable("wireless_inventory_unavailable") from exc
    return candidate


class MonitorApi(KismetAdapter):
    """Only the isolated manager has the credential needed to change a datasource."""

    def list_sources(self):
        return records(self._request("/datasource/all_sources.json"))

    def add(self, uuid):
        definition = (f"{MONITOR_INTERFACE}:type=linuxwifi,name={SOURCE_NAME},uuid={uuid},"
                      f"vif={MONITOR_VIF},retry=false,filter_mgmt=true")
        self._request("/datasource/add_source.cmd", {"json": json.dumps({"definition": definition})},
                      text_reply=True, timeout=17)

    def _command(self, uuid, action):
        self._request(f"/datasource/by-uuid/{str(UUID(uuid))}/{action}_source.cmd", {"json": "{}"},
                      text_reply=True, timeout=17)

    def close_source(self, uuid):
        self._command(uuid, "close")

    def open_source(self, uuid):
        self._command(uuid, "open")


FIELD = "kismet.datasource."


def is_local_monitor(row):
    kind = row.get(FIELD + "type_driver")
    definition = row.get(FIELD + "definition")
    if not isinstance(definition, str):
        return False
    interface, _, options = definition.partition(":")
    vifs = [option.partition("=")[2] for option in options.split(",") if option.startswith("vif=")]
    return (isinstance(kind, dict) and kind.get("kismet.datasource.driver.type") == "linuxwifi"
            and row.get(FIELD + "remote") in (False, 0)
            and row.get(FIELD + "name") == SOURCE_NAME
            and row.get(FIELD + "interface") == MONITOR_INTERFACE
            and interface == MONITOR_INTERFACE and vifs == [MONITOR_VIF]
            and row.get(FIELD + "retry") in (False, 0)
            and "filter_mgmt=true" in options.split(","))


class MonitorManager:
    def __init__(self, config, api, *, detect=select_radio, net=NET, clock=time.monotonic):
        self.config = config
        self.api = api
        self.detect = detect
        self.net = net
        self.clock = clock
        self.last_attempt = float("-inf")
        self.last_radio = None

    def owned_source(self, sources):
        matching = [row for row in sources if isinstance(row.get(FIELD + "uuid"), str)
                    and row[FIELD + "uuid"].lower() == self.config.datasource_uuid]
        if len(matching) > 1 or (matching and not is_local_monitor(matching[0])):
            raise Unavailable("monitor_uuid_conflict")
        return matching[0] if matching else None

    def close(self):
        row = self.owned_source(self.api.list_sources())
        if row and row.get(FIELD + "running") in (True, 1):
            self.api.close_source(self.config.datasource_uuid)

    def check(self):
        """Return a compact status and avoid changing any datasource not assigned by this manager."""
        try:
            return self._check()
        except Unavailable as exc:
            return "degraded", str(exc), None
        except KismetError as exc:
            return "degraded", exc.code.lower(), None

    def _check(self):
        try:
            radio = self.detect(self.config)
        except Unavailable:
            self.last_radio = None
            try:
                self.close()
            except KismetError:
                # Preserve the physical reason if the Kismet instance is also unavailable.
                pass
            raise

        sources = self.api.list_sources()
        row = self.owned_source(sources)
        if any(other is not row and other.get(FIELD + "running") in (True, 1)
               and (other.get(FIELD + "interface") in (MONITOR_INTERFACE, MONITOR_VIF)
                    or other.get(FIELD + "capture_interface") in (MONITOR_INTERFACE, MONITOR_VIF))
               for other in sources):
            if row and row.get(FIELD + "running") in (True, 1):
                self.api.close_source(self.config.datasource_uuid)
            raise Unavailable("monitor_source_conflict")
        if row and row.get(FIELD + "running") in (True, 1):
            capture_name = row.get(FIELD + "capture_interface")
            identity_ok = False
            if capture_name in (MONITOR_INTERFACE, MONITOR_VIF):
                try:
                    identity_ok = (self.net / capture_name / "phy80211").resolve(strict=True) == radio.phy
                except (OSError, RuntimeError):
                    pass
            if not identity_ok:
                self.api.close_source(self.config.datasource_uuid)
                raise Unavailable("monitor_capture_identity_mismatch")
            if row.get(FIELD + "paused") in (False, 0) and row.get(FIELD + "error") in (False, 0):
                return "ready", "", self.config.datasource_uuid
            return "degraded", "monitor_source_unhealthy", None

        if self.last_radio == radio and self.clock() - self.last_attempt < RETRY_SECONDS:
            return "degraded", "monitor_waiting_for_source", None
        if self.detect(self.config) != radio:
            raise Unavailable("monitor_identity_changed")
        self.last_attempt, self.last_radio = self.clock(), radio
        if row:
            self.api.open_source(self.config.datasource_uuid)
        else:
            self.api.add(self.config.datasource_uuid)
        return "starting", "monitor_waiting_for_source", None


def write_status(path, state, reason, uuid):
    data = {"state": state, "reason": reason, "timestamp_ms": time.time_ns() // 1_000_000}
    if uuid:
        data["datasource_uuid"] = uuid
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False, encoding="utf-8") as stream:
        temporary = Path(stream.name)
        try:
            json.dump(data, stream, separators=(",", ":"))
            stream.flush()
            os.fchmod(stream.fileno(), 0o644)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    logging.basicConfig(level=logging.INFO)
    status = Path("/run/piagent-wireless/monitor.json")
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    try:
        config = MonitorConfig(**json.loads((credentials / "monitor.json").read_text(encoding="utf-8")))
        key = (credentials / "monitor.key").read_text(encoding="ascii").strip()
        manager = MonitorManager(config, MonitorApi(f"http://127.0.0.1:{config.kismet_port}", key))
    except (OSError, TypeError, ValueError):
        manager = None
    stop = Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    previous = None
    try:
        while not stop.is_set():
            state = manager.check() if manager else ("degraded", "monitor_config_invalid", None)
            if state != previous:
                LOG.info("Wi-Fi datasource %s (%s)", state[0], state[1])
                previous = state
            write_status(status, *state)
            stop.wait(POLL_SECONDS)
    finally:
        if manager:
            try:
                manager.close()
            except (KismetError, Unavailable):
                LOG.warning("Could not close the assigned Kismet datasource during shutdown.")


if __name__ == "__main__":
    main()
