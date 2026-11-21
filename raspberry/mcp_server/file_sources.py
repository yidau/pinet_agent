"""Restricted offline inventory, active Bluetooth observations and replay control."""

import json
import os
from pathlib import Path
import re
import shutil
import socket
import sqlite3
import stat
import struct
from datetime import datetime, timezone

from .capabilities import CapabilityStatus as State
from .kismet_adapter import KismetError, PAGE_SIZE


CAPTURES = Path("/var/lib/piagent-captures")
CONTROL = Path("/run/piagent-replay.sock")
ALLOW_REPLAY = Path("/etc/piagent-sources/allow-replay")
BT_CONFLICT = Path("/etc/piagent-sources/bluetooth-conflict")
BT_UUID = "7A459538-7417-4068-9BD0-D7F2E0D405B4"
MAX_BYTES = 64 * 1024 * 1024
MAX_FILES = 64
CAPTURE_OWNER_UID = 0
FILE_NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,95}")
PCAPS = {b"\xd4\xc3\xb2\xa1": "<", b"\xa1\xb2\xc3\xd4": ">",
         b"\x4d\x3c\xb2\xa1": "<", b"\xa1\xb2\x3c\x4d": ">"}
FORMATS = {".pcap": "PCAP", ".pcapng": "PCAPNG", ".kismet": "KismetDB", ".kismetdb": "KismetDB"}
HELPERS = {"PCAP": "kismet_cap_pcapfile", "PCAPNG": "kismet_cap_pcapfile", "KismetDB": "kismet_cap_kismetdb"}


class SourceError(Exception):
    def __init__(self, status, code, message):
        super().__init__(message)
        self.status, self.code = State(status), code


def limited(message):
    return SourceError(State.DEGRADED, "CAPABILITY_UNAVAILABLE", message)


def invalid(message):
    return SourceError(State.ERROR, "INVALID_CAPTURE", message)


def check_directory(directory):
    try:
        info = directory.lstat()
    except OSError:
        raise limited("The offline capture directory is unavailable.") from None
    if not stat.S_ISDIR(info.st_mode) or (os.name == "posix" and (info.st_uid != CAPTURE_OWNER_UID or info.st_mode & 0o022)):
        raise limited("Install a root-owned capture directory writable only by its administrator.")


def capture_metadata(name, directory=CAPTURES):
    check_directory(directory)
    if not isinstance(name, str) or not FILE_NAME.fullmatch(name):
        raise invalid("Select a plain filename from list_captures.")
    path = directory / name
    fmt = FORMATS.get(path.suffix.lower())
    if not fmt:
        raise invalid("Unsupported capture file extension.")
    try:
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise invalid("The capture must be a regular file without links.")
        if os.name == "posix" and (info.st_uid != CAPTURE_OWNER_UID or info.st_mode & 0o022):
            raise invalid("Capture files must be installed read-only for the services by their administrator.")
        if not 0 < info.st_size <= MAX_BYTES:
            raise invalid("The selected file must contain data and be at most 64 MiB.")
        with path.open("rb") as stream:
            if not os.path.samestat(info, os.fstat(stream.fileno())):
                raise invalid("The selected capture changed during validation.")
            header = stream.read(32)
        if fmt == "PCAP":
            order = PCAPS.get(header[:4])
            if not order or len(header) < 24 or struct.unpack_from(order + "HH", header, 4) != (2, 4):
                raise invalid("Invalid PCAP header.")
        elif fmt == "PCAPNG":
            order = {b"\x4d\x3c\x2b\x1a": "<", b"\x1a\x2b\x3c\x4d": ">"}.get(header[8:12])
            if not order or header[:4] != b"\x0a\x0d\x0d\x0a" or len(header) < 28:
                raise invalid("Invalid PCAPNG section header.")
            size = struct.unpack_from(order + "I", header, 4)[0]
            if size < 28 or size > info.st_size or size % 4 or struct.unpack_from(order + "H", header, 12)[0] != 1:
                raise invalid("Invalid PCAPNG section length or version.")
        else:
            if not header.startswith(b"SQLite format 3\0"):
                raise invalid("Invalid KismetDB header.")
            db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro&immutable=1", uri=True)
            try:
                db.execute("PRAGMA trusted_schema=OFF")
                required = {row[0] for row in db.execute(
                    "SELECT lower(name) FROM sqlite_schema WHERE type='table' AND lower(name) IN ('kismet','packets','data')")}
                if required != {"kismet", "packets", "data"} or not db.execute("SELECT db_version FROM KISMET LIMIT 1").fetchone():
                    raise invalid("The SQLite file lacks the required Kismet log tables.")
            finally:
                db.close()
    except FileNotFoundError:
        raise invalid("The selected capture no longer exists.") from None
    except (OSError, sqlite3.Error):
        raise invalid("The selected capture could not be read as a supported file.") from None
    return {"id": name, "filename": name, "format": fmt, "size_bytes": info.st_size,
            "modified_at": datetime.fromtimestamp(info.st_mtime, timezone.utc).isoformat(), "status": "AVAILABLE"}


def list_files(directory=CAPTURES):
    check_directory(directory)
    rows = []
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                if len(rows) >= MAX_FILES:
                    raise limited("The capture directory exceeds the 64-file limit.")
                try:
                    rows.append(capture_metadata(entry.name, directory))
                except SourceError as error:
                    rows.append({"filename": entry.name[:96], "id": entry.name[:96], "status": error.status, "reason": str(error)})
    except OSError:
        raise limited("Cannot read the offline capture directory.") from None
    return sorted(rows, key=lambda row: row["filename"])


def control(action, capture_id=None):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(8)
            sock.connect(str(CONTROL))
            sock.sendall(json.dumps({"action": action, "capture_id": capture_id}).encode() + b"\n")
            with sock.makefile("rb") as stream:
                line = stream.readline(8193)
            if not line or len(line) > 8192:
                raise ValueError()
            payload = json.loads(line)
            if "error_code" in payload:
                raise SourceError(payload["status"], payload["error_code"], payload["message"])
            return payload
    except (OSError, ValueError, KeyError, AttributeError):
        raise limited("The local replay control service did not respond.") from None


def bt_flag(sources):
    if BT_CONFLICT.is_file():
        return State.DEGRADED, "The operator recorded a conflict with BLE GATT; Bluetooth scanning is disabled."
    if sources is not None:
        active = [s for s in sources if s["driver"] == "linuxbluetooth" and s["uuid"].upper() == BT_UUID
                  and s["running"] and not s["error"] and not s["paused"]]
        if active:
            return State.AVAILABLE, ""
    if not (shutil.which("kismet_cap_linux_bluetooth") or Path("/usr/bin/kismet_cap_linux_bluetooth").is_file()):
        return State.UNAVAILABLE, "Install the Kismet Linux Bluetooth capture helper."
    if sources is None:
        return State.ERROR, "Kismet datasource state could not be read."
    return State.DEGRADED, "The operator-controlled Bluetooth scan is inactive or unavailable; check BLE coexistence."


class SourceService:
    tool_names = frozenset({"get_bluetooth_devices", "get_bluetooth_device_details", "list_captures",
                            "get_capture_metadata", "get_capture_status", "replay_capture", "stop_capture_replay"})

    def __init__(self, adapter, directory=CAPTURES):
        self.adapter, self.directory = adapter, directory

    def capabilities(self, sources):
        available = (State.AVAILABLE, "")
        bt = bt_flag(sources)
        bt_details = bt
        if bt[0] == State.AVAILABLE:
            try:
                devices, _ = self.adapter.get_source_devices(BT_UUID, phy="Bluetooth")
                if not devices:
                    bt_details = State.DEGRADED, "No Bluetooth devices have been observed in this source view."
            except KismetError as error:
                bt_details = bt = State.ERROR, str(error)
        status = available if CONTROL.is_socket() else (State.DEGRADED, "Configure the local replay control service.")
        rows = []
        try:
            rows = list_files(self.directory)
            inventory = available
        except SourceError as error:
            inventory = error.status, str(error)
        replay = inventory
        valid = [row for row in rows if row["status"] == State.AVAILABLE]
        if inventory == available:
            if not rows:
                replay = State.DEGRADED, "No offline capture files are installed."
            elif not valid:
                replay = State.ERROR, "No file passed capture validation."
            elif sources is None:
                replay = State.ERROR, "Kismet datasource state could not be read."
            elif not any(shutil.which(HELPERS[row["format"]]) for row in valid):
                replay = State.DEGRADED, "The required Kismet file helper is unavailable."
            elif status != available:
                replay = status
            elif not ALLOW_REPLAY.is_file():
                replay = State.DEGRADED, "The administrator has not enabled file replay."
        stop = (State.DEGRADED, "There is no active replay.")
        if status == available:
            try:
                state = control("status")
                if state.get("upstream_error"):
                    replay = State.ERROR, state["upstream_error"]
                    stop = available
                elif state["state"] in ("running", "starting"):
                    stop, replay = available, (State.DEGRADED, "Another replay is running.")
            except SourceError as error:
                status = error.status, str(error)
                if replay == available:
                    replay = status
        metadata = available if valid else replay
        states = {"list_captures": inventory, "get_capture_metadata": metadata,
                  "get_bluetooth_devices": bt, "get_bluetooth_device_details": bt_details,
                  "get_capture_status": status, "replay_capture": replay, "stop_capture_replay": stop}
        features = {"bluetooth_scanning": {"status": bt[0], "reason": bt[1]},
                    "pcap_replay": {"status": (State.AVAILABLE if stop == available and replay[0] != State.ERROR
                                               else replay[0]),
                                    "reason": ("" if stop == available and replay[0] != State.ERROR else replay[1])}}
        if status == available and state.get("state") == "error":
            features["pcap_replay"] = {"status": State.ERROR, "reason": state.get("reason", "Last replay failed.")}
        return states, features

    def call(self, name, sources, *, capture_id=None, device_id=None, confirm=False):
        if name == "list_captures":
            return {"captures": list_files(self.directory), "source": "local capture directory"}
        if name == "get_capture_metadata":
            return {**capture_metadata(capture_id, self.directory), "source": "local capture directory"}
        if name == "get_capture_status":
            data = control("status")
            data["source"] = "local replay controller"
            if sources is not None and data.get("datasource") and any(
                    source["uuid"].upper() == data["datasource"].upper() for source in sources):
                try:
                    devices, total = self.adapter.get_source_devices(data["datasource"])
                    data.update(observed_devices=[{key: value for key, value in device.items() if key != "samples"}
                                                   for device in devices], total_devices=total)
                except KismetError as error:
                    data["observation_reason"] = str(error)
            return data
        if name in ("replay_capture", "stop_capture_replay"):
            if confirm is not True:
                raise SourceError(State.DEGRADED, "CONFIRMATION_REQUIRED", "Explicit device operator confirmation is required.")
            if name == "stop_capture_replay":
                return control("stop")
            capture_metadata(capture_id, self.directory)
            if sources is None:
                raise limited("Cannot confirm Kismet datasource state.")
            return control("start", capture_id)
        state, reason = bt_flag(sources)
        if state != State.AVAILABLE:
            raise SourceError(state, "CAPABILITY_UNAVAILABLE", reason)
        devices, total = self.adapter.get_source_devices(BT_UUID, phy="Bluetooth")
        data = [{**{k: v for k, v in device.items() if k != "samples"}, "observation_source": "bluetooth_scan"}
                for device in devices[:PAGE_SIZE]]
        if name == "get_bluetooth_devices":
            return {"devices": data, "total": total, "truncated": total > len(data), "observation_mode": "Active Scan"}
        for device in data:
            if device["id"] == device_id:
                return {"device": device}
        if not data:
            raise limited("No Bluetooth devices have been observed in this source view.")
        raise SourceError(State.ERROR, "DEVICE_NOT_IN_VIEW", "Select a device from the current Bluetooth page.")
