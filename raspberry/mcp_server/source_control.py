"""Socket-activated local replay controller and fixed, operator-started Bluetooth unit."""

import base64
import json
import os
from pathlib import Path
import re
import shutil
import socket
import struct
import subprocess
import sys
import time
import uuid

from .capabilities import CapabilityStatus as State
from .file_sources import (
    ALLOW_REPLAY, BT_UUID, CAPTURES, HELPERS, MAX_FILES, SourceError, capture_metadata, capture_path,
    limited, phone_directory,
)
from .kismet_adapter import KismetAdapter, KismetError, records


HOME_DIR = Path("/var/lib/piagent-kismet")
STATE_FILE = HOME_DIR / "pocketnet-replay.json"
BT_TOKEN = Path("/run/piagent-bt-scan/key")
MAX_SECONDS = 600
PPS = 50


def fields(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines() if line and not line.startswith("#") and "=" in line)


def port():
    return int(fields(Path("/etc/kismet/piagent.conf"))["httpd_port"])


class AdminAdapter(KismetAdapter):
    """Only instantiated in the local controller/administrator process."""

    def __init__(self):
        super().__init__(f"http://127.0.0.1:{port()}", "")
        auth = fields(HOME_DIR / ".kismet/kismet_httpd.conf")
        basic = (auth["httpd_username"] + ":" + auth["httpd_password"]).encode()
        self._auth = "Basic " + base64.b64encode(basic).decode()

    def _headers(self):
        return {"Authorization": self._auth, "Accept": "application/json"}

    def command(self, path, args=None, *, text=False):
        return self._request(path, {"json": json.dumps(args or {})}, text_reply=text, timeout=4)

    def eof_event(self, filename, since):
        path = str(capture_path(filename, CAPTURES))
        pcap = f"Pcapfile '{path}' closed: "
        kdb = f"KismetDB '{path}' closed, all packets and data processed."
        for msg in reversed(records(self._request("/messagebus/all_messages.json"))):
            if msg.get("kismet.messagebus.message_time", 0) < since:
                continue
            value = msg.get("kismet.messagebus.message_string", "")
            if kdb in value or pcap + "end of pcapfile reached" in value:
                return "completed"
            if pcap in value:
                return "error"
        return None


def save_state(data):
    temp = STATE_FILE.with_suffix(".tmp")
    temp.write_text(json.dumps(data))
    os.replace(temp, STATE_FILE)


class Replay:
    def __init__(self, adapter):
        self.api = adapter
        self.data = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {"state": "idle"}
        self.deadline = time.monotonic() + max(0, min(MAX_SECONDS,
            self.data.get("started", 0) + MAX_SECONDS - time.time()))

    @property
    def active(self):
        return self.data["state"] in ("starting", "running")

    def source(self):
        return next((s for s in self.api.get_datasources()
                     if s["uuid"].upper() == self.data["datasource"] and s["name"] == self.data["name"]
                     and s["driver"] in ("pcapfile", "kismetdb")), None)

    def finish(self, state, reason, source):
        if source and source["running"]:
            self.api.command(f"/datasource/by-uuid/{self.data['datasource']}/close_source.cmd")
        self.data.update(state=state, reason=reason)
        save_state(self.data)

    def poll(self):
        if not self.active:
            return
        source = self.source()
        if not source and self.data["state"] == "starting" and time.monotonic() < self.deadline - MAX_SECONDS + 20:
            # A command can time out while Kismet is still opening the helper.
            return
        if not source:
            self.finish("error", "Kismet no longer reports this file source.", None)
        elif time.monotonic() >= self.deadline:
            self.finish("stopped", "The ten-minute playback time limit was reached.", source)
        else:
            event = self.api.eof_event(self.data["filename"], self.data["started"])
            if event:
                reason = "Kismet reached end of file." if event == "completed" else "Kismet reported a file read error."
                self.finish(event, reason, source)
            elif source["error"] or not source["running"]:
                self.finish("error", "Kismet reports a closed or failed file source.", source)
            elif self.data["state"] == "starting":
                self.data["state"] = "running"
                save_state(self.data)

    def start(self, filename, *, phone_operator=False):
        if not phone_operator and not ALLOW_REPLAY.is_file():
            raise limited("Offline replay has not been enabled by the administrator.")
        if self.active:
            raise limited("A replay is already running.")
        meta = capture_metadata(filename)
        path = capture_path(filename, CAPTURES)
        if not shutil.which(HELPERS[meta["format"]]):
            raise limited("Install the corresponding Kismet file helper.")
        driver = "kismetdb" if meta["format"] == "KismetDB" else "pcapfile"
        ident = str(uuid.uuid5(uuid.NAMESPACE_URL, "urn:piagent:offline:" + filename)).upper()
        name = "PocketNet-file-" + ident
        sources = self.api.get_datasources()
        if any(s["running"] and s["driver"] in ("pcapfile", "kismetdb") for s in sources):
            raise limited("Another file datasource is running in Kismet.")
        existing = next((s for s in sources if s["uuid"].upper() == ident), None)
        if not existing and sum(s["name"].startswith("PocketNet-file-") for s in sources) >= MAX_FILES:
            raise limited("The Kismet session already has 64 PocketNet file sources; reuse an existing file.")
        if existing and (existing["driver"] != driver or existing["name"] != name or
                         existing["interface"] != str(path)):
            raise limited("The capture source identifier is already in use.")
        # Messagebus timestamps have second precision. Don't match the previous
        # EOF when the same small file is opened twice during the same second.
        if existing and self.api.eof_event(filename, int(time.time())):
            time.sleep(1.05)
        self.data = {"state": "starting", "filename": filename, "datasource": ident,
                     "name": name, "started": int(time.time()), "pps": PPS}
        save_state(self.data)
        self.deadline = time.monotonic() + MAX_SECONDS
        if existing:
            self.api.command(f"/datasource/by-uuid/{ident}/open_source.cmd")
        else:
            definition = f"{path}:type={driver},uuid={ident},name={name},pps={PPS},retry=false"
            self.api.command("/datasource/add_source.cmd", {"definition": definition})
        src = self.source()
        if not src or not src["running"] or src["error"]:
            if self.api.eof_event(filename, self.data["started"]) == "completed":
                self.finish("completed", "Kismet reached end of file.", src)
                return
            self.finish("error", "Kismet could not open the selected capture.", src)
            raise SourceError(State.ERROR, "REPLAY_OPEN_FAILED", self.data["reason"])
        self.data["state"] = "running"
        save_state(self.data)

    def execute(self, request, *, phone_operator=False):
        action = request.get("action")
        if action == "phone-start":
            if not phone_operator:
                raise limited("The enrolled-phone gateway must submit this operation.")
            self.start(request.get("capture_id"), phone_operator=True)
        elif action == "start":
            self.start(request.get("capture_id"))
        elif action == "stop":
            if not self.active:
                raise limited("There is no active replay.")
            self.finish("stopped", "Stopped by the device operator.", self.source())
        elif action != "status":
            raise limited("Unknown replay operation.")
        return self.data


def controller():
    replay = Replay(AdminAdapter())
    # systemd owns the listening socket; the single worker serializes requests
    # and reaps the Kismet file helper even if the phone disconnects.
    with socket.socket(fileno=3) as listener:
        listener.settimeout(0.6)
        last_request = time.monotonic()
        while True:
            try:
                replay.poll()
                replay.data.pop("upstream_error", None)
            except KismetError as error:
                replay.data["upstream_error"] = str(error)
            try:
                conn, _ = listener.accept()
            except socket.timeout:
                if replay.active or time.monotonic() - last_request < 10:
                    continue
                return
            with conn:
                last_request = time.monotonic()
                conn.settimeout(1)
                try:
                    with conn.makefile("rb") as incoming:
                        raw = incoming.readline(1025)
                    if len(raw) > 1024 or not raw.endswith(b"\n"):
                        raise ValueError()
                    request = json.loads(raw)
                    if not isinstance(request, dict):
                        raise ValueError()
                    phone_operator = False
                    if request.get("action") == "phone-start":
                        credentials = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("iII"))
                        _, uid, _ = struct.unpack("iII", credentials)
                        phone_operator = uid == phone_directory(CAPTURES).stat().st_uid
                    response = replay.execute(request, phone_operator=phone_operator)
                except SourceError as error:
                    response = {"status": error.status, "error_code": error.code, "message": str(error)}
                except KismetError as error:
                    response = {"status": "ERROR", "error_code": error.code, "message": str(error)}
                except (ValueError, OSError):
                    response = {"status": "ERROR", "error_code": "REPLAY_REQUEST", "message": "Invalid or interrupted replay request."}
                try:
                    conn.sendall(json.dumps(response).encode() + b"\n")
                except OSError:
                    pass


def bt_key_name():
    # systemd assigns a fresh ID to each service invocation.
    return "PocketNet-BT-" + uuid.UUID(os.environ["INVOCATION_ID"]).hex


class BluetoothPreflightError(Exception):
    """Stable ExecStartPre exit status, exposed to the phone by the operator API."""
    def __init__(self, exit_status, message):
        super().__init__(message)
        self.exit_status = exit_status


def read_controller_info(control):
    # Linux Bluetooth management protocol: Read Controller Information for hci0.
    # Management integers are little-endian regardless of the host architecture.
    opcode, index = 0x0004, 0
    control.settimeout(3)
    control.sendall(struct.pack("<HHH", opcode, index, 0))
    deadline = time.monotonic() + 3
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError()
        control.settimeout(remaining)
        packet = control.recv(1024)
        if not packet:
            raise OSError("Bluetooth management socket closed")
        if len(packet) < 9:
            continue
        event, controller, length, command, status = struct.unpack_from("<HHHHB", packet)
        if controller != index or event not in (1, 2) or command != opcode:
            continue
        if length != len(packet) - 6 or status:
            raise OSError(f"Invalid controller information response (status {status:#x})")
        if event == 2:  # Command Status; only Command Complete carries the data.
            continue
        if length < 3 + 17:
            raise OSError("Truncated controller information")
        address, _, _, _, settings = struct.unpack_from("<6sBHII", packet, 9)
        return address, settings


def controller_info():
    import ctypes

    # Older supported CPython versions do not expose the channel in bind().
    # sockaddr_hci is three native-endian uint16s: AF_BLUETOOTH, HCI_DEV_NONE,
    # HCI_CHANNEL_CONTROL. Only the read-only management command above is sent.
    try:
        with socket.socket(socket.AF_BLUETOOTH, socket.SOCK_RAW, socket.BTPROTO_HCI) as control:
            sockaddr = struct.pack("=HHH", socket.AF_BLUETOOTH, 0xffff, 3)
            bind = ctypes.CDLL(None, use_errno=True).bind
            bind.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint]
            if bind(control.fileno(), sockaddr, len(sockaddr)) != 0:
                err = ctypes.get_errno()
                raise OSError(err, os.strerror(err))
            return read_controller_info(control)
    except TimeoutError:
        raise BluetoothPreflightError(75, "Timed out reading hci0 controller settings.") from None
    except OSError as exc:
        raise BluetoothPreflightError(69, f"Could not read hci0 controller settings: {exc}") from None


def check_bluetooth_ready():
    address, settings = controller_info()
    required = (1 << 0) | (1 << 7) | (1 << 9)  # powered, BR/EDR, LE
    if address in (bytes(6), b"\xff" * 6) or settings & required != required:
        raise BluetoothPreflightError(78, "hci0 needs a valid address, power, and both LE and BR/EDR modes.")
    # Check the same controller via BlueZ. Reading this property never requests discovery.
    try:
        prop = subprocess.run(
            ["/usr/bin/busctl", "--system", "--timeout=3s", "get-property",
             "org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1", "Discovering"],
            capture_output=True, text=True, timeout=4, check=True,
        )
    except (OSError, subprocess.SubprocessError):
        raise BluetoothPreflightError(76, "Could not read the BlueZ hci0 discovery state.") from None
    if prop.stdout.strip() == "b true":
        raise BluetoothPreflightError(73, "BlueZ discovery is already busy.")
    if prop.stdout.strip() != "b false":
        raise BluetoothPreflightError(76, "BlueZ returned an unknown hci0 discovery state.")


def bt_receipt():
    # /run is root-owned; the unprivileged helper can write only its own runtime directory.
    return Path("/run") / (bt_key_name() + ".issued")


def bluetooth_retire():
    receipt = bt_receipt()
    if receipt.is_file():
        try:
            AdminAdapter().command("/auth/apikey/revoke.cmd", {"name": bt_key_name()}, text=True)
        finally:
            receipt.unlink(missing_ok=True)


def bluetooth_prepare():
    check_bluetooth_ready()
    adapter = AdminAdapter()
    key = adapter.command("/auth/apikey/generate.cmd", {
        "name": bt_key_name(), "role": "datasource", "duration": 150}, text=True).strip()
    if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{8,2048}", key):
        raise SystemExit("Kismet did not issue a datasource credential.")
    try:
        bt_receipt().touch(mode=0o600, exist_ok=False)
    except OSError:
        adapter.command("/auth/apikey/revoke.cmd", {"name": bt_key_name()}, text=True)
        raise
    # RuntimeDirectory is writable by the child; never follow a child-supplied
    # path with privilege. O_EXCL also rejects links on a retry.
    with open(BT_TOKEN, "x") as stream:
        stream.write(json.dumps({"key": key, "port": port()}))
        os.fchmod(stream.fileno(), 0o400)
        import pwd
        user = pwd.getpwnam("piagent-bt-scan")
        os.fchown(stream.fileno(), user.pw_uid, user.pw_gid)


def bluetooth_run():
    config = json.loads(BT_TOKEN.read_text())
    BT_TOKEN.unlink()
    binary = "/usr/bin/kismet_cap_linux_bluetooth"
    os.execv(binary, [binary, "--connect", f"127.0.0.1:{config['port']}", "--disable-retry",
                      "--apikey", config["key"], "--source",
                      f"hci0:type=linuxbluetooth,name=PocketNet-Bluetooth,uuid={BT_UUID},probe=off,retry=false"])


if __name__ == "__main__":
    if sys.argv[1] in ("start", "stop", "status"):
        import argparse
        from .file_sources import control
        parser = argparse.ArgumentParser(description="Operator control for one offline file source.")
        parser.add_argument("action", choices=("start", "stop", "status"))
        parser.add_argument("capture_id", nargs="?")
        parser.add_argument("--confirm", action="store_true")
        args = parser.parse_args()
        if args.action != "status" and not args.confirm:
            parser.error("Pass --confirm for a state change.")
        try:
            print(json.dumps(control(args.action, args.capture_id), ensure_ascii=False))
        except SourceError as error:
            raise SystemExit(str(error))
    elif sys.argv[1] == "bt-retire":
        bluetooth_retire()
    elif sys.argv[1] == "bt-prepare":
        try:
            bluetooth_prepare()
        except BluetoothPreflightError as error:
            print(error, file=sys.stderr)
            sys.exit(error.exit_status)
    else:
        {"controller": controller, "bt-run": bluetooth_run}[sys.argv[1]]()
