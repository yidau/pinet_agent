"""Socket-activated local replay controller and fixed, operator-started Bluetooth unit."""

import base64
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import uuid

from .capabilities import CapabilityStatus as State
from .file_sources import ALLOW_REPLAY, BT_UUID, CAPTURES, HELPERS, MAX_FILES, SourceError, capture_metadata, limited
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
        path = str(CAPTURES / filename)
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

    def start(self, filename):
        if not ALLOW_REPLAY.is_file():
            raise limited("Offline replay has not been enabled by the administrator.")
        if self.active:
            raise limited("A replay is already running.")
        meta = capture_metadata(filename)
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
                         existing["interface"] != str(CAPTURES / filename)):
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
            definition = f"{CAPTURES / filename}:type={driver},uuid={ident},name={name},pps={PPS},retry=false"
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

    def execute(self, request):
        action = request.get("action")
        if action == "start":
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
                    response = replay.execute(request)
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


def bluetooth_prepare():
    # Only the unit's privileged pre-start step can read the Kismet admin login.
    # The HCI helper receives a short-lived datasource-only token.
    if not Path("/sys/class/bluetooth/hci0").is_dir():
        raise SystemExit("The onboard hci0 is unavailable.")
    # The upstream dual-mode helper can enable BR/EDR, LE or power. Only
    # launch it on an already-powered dual-mode controller with idle discovery.
    locale = {**os.environ, "LC_ALL": "C"}
    info = subprocess.run(["/usr/bin/btmgmt", "--index", "0", "info"], capture_output=True,
                          text=True, check=True, timeout=3, env=locale).stdout
    settings = next((line.split(":", 1)[1].split() for line in info.splitlines()
                     if line.strip().startswith("current settings:")), [])
    if not {"powered", "le", "br/edr"} <= set(settings):
        raise SystemExit("The controller is not already powered in both LE and BR/EDR modes.")
    address = re.search(r"(?i)\baddr\s+([0-9a-f]{2}(?::[0-9a-f]{2}){5})\b", info)
    if not address:
        raise SystemExit("The address of hci0 is unavailable.")
    bluez = subprocess.run(["/usr/bin/bluetoothctl", "show", address.group(1)], capture_output=True,
                           text=True, check=True, timeout=3, env=locale).stdout
    if not re.search(r"(?m)^\s*Discovering:\s*no\s*$", bluez):
        raise SystemExit("BlueZ discovery is busy or its state is unknown.")
    adapter = AdminAdapter()
    key = adapter.command("/auth/apikey/generate.cmd", {
        "name": bt_key_name(), "role": "datasource", "duration": 150}, text=True).strip()
    if not re.fullmatch(r"[A-Za-z0-9._~+/=-]{8,2048}", key):
        raise SystemExit("Kismet did not issue a datasource credential.")
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
        AdminAdapter().command("/auth/apikey/revoke.cmd", {"name": bt_key_name()}, text=True)
    else:
        {"controller": controller, "bt-prepare": bluetooth_prepare, "bt-run": bluetooth_run}[sys.argv[1]]()
