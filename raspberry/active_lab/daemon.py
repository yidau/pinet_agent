"""RAM-first MDK4 broker. No public listener, shell, raw argv, or automatic target selection.

The lab operator must install /etc/pocketnet/lab-profiles.json locally. A profile
must describe a physically isolated, owned test AP; observed Wi-Fi is never
itself an authorization grant.
"""
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import threading
import time
from uuid import uuid4

from raspberry.wireless.wireless_manager import (
    MONITOR_INTERFACE, PAUSE_MARKER, RUNTIME_DIR, MonitorConfig, kismet_operation,
    select_radio,
)

RUN = Path("/run/piagent-radio")
SOCKET = RUN / "lab.sock"
MONITOR = RUNTIME_DIR / "monitor.json"
CONFIG = Path("/etc/piagent-kismet/monitor.json")
PROFILES = Path("/etc/pocketnet/lab-profiles.json")
LAB_IFACE = "pn-labmon"
LEASE_SECONDS = 20
HARD_SECONDS = 600
HEX_MAC = re.compile(r"^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$")
SAFE_SSID = re.compile(r"^[A-Za-z0-9_.-]{1,24}$")
SAFE_PROFILE = re.compile(r"^[a-z0-9_-]{1,40}$")
KINDS = {"probe", "ssid_lab"}
MDK4 = "/usr/sbin/mdk4"
IW = "/usr/sbin/iw"
IP = "/usr/sbin/ip"


def read_json(path):
    try:
        data = path.read_text(encoding="utf-8")
        value = json.loads(data) if len(data) <= 8192 else None
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def profile_for(profile_id, bssid, ssid, channel):
    """All target values are matched against a root-provisioned lab profile."""
    if profile_id and not SAFE_PROFILE.fullmatch(profile_id):
        return None
    root = read_json(PROFILES)
    if root.get("schema") != 1:
        return None
    entries = root.get("profiles")
    if not isinstance(entries, list) or len(entries) > 8:
        return None
    for p in entries:
        if not isinstance(p, dict) or (profile_id and p.get("id") != profile_id):
            continue
        if p.get("rf_isolated") is not True or p.get("enabled") is not True:
            return None
        if not isinstance(p.get("allowed_tests"), list):
            return None
        if not set(p["allowed_tests"]).issubset(KINDS):
            return None
        if not isinstance(p.get("ssid"), str) or not SAFE_SSID.fullmatch(p["ssid"]):
            return None
        if not isinstance(p.get("bssid"), str) or not HEX_MAC.fullmatch(p["bssid"]):
            return None
        if not isinstance(p.get("simulated_bssid"), str) or not HEX_MAC.fullmatch(p["simulated_bssid"]):
            return None
        if p["simulated_bssid"] == p["bssid"] or p["simulated_bssid"].startswith("ff:"):
            return None
        if type(p.get("channel")) is not int or not 1 <= p["channel"] <= 11:
            return None
        if (p["bssid"], p["ssid"], str(p["channel"])) != (bssid, ssid, channel):
            return None
        return p
    return None


def valid_observation(o):
    if not isinstance(o, dict):
        return False
    if not isinstance(o.get("bssid"), str) or not isinstance(o.get("ssid"), str):
        return False
    if not isinstance(o.get("channel"), str) or not re.fullmatch(r"[1-9]|10|11", o["channel"]):
        return False
    t = o.get("last_seen_ms")
    return type(t) is int and 0 <= int(time.time() * 1000) - t <= 60000


def radio_identity():
    config = MonitorConfig(**read_json(CONFIG))
    return select_radio(config)


def run_checked(*argv):
    subprocess.run(argv, check=True, timeout=4, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)


class Lab:
    def __init__(self):
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        self.phase = "passive"
        self.reason = ""
        self.session = ""
        self.owner = ""
        self.profile = {}
        self.kind = ""
        self.started_ms = 0
        self.finished_ms = 0
        self.deadline = 0.0
        self.hard_deadline = 0.0
        self.proc = None
        self.restored = True
        self.thread = None
        # Recovery after daemon restart must never resume an old transmitter.
        with kismet_operation():
            marker = read_json(PAUSE_MARKER)
            if marker.get("owner") == "radio_lab":
                PAUSE_MARKER.unlink(missing_ok=True)

    def status(self, accepted=True):
        with self.lock:
            p = self.profile
            return dict(accepted=accepted, phase=self.phase, reason=self.reason,
                        session_id=self.session, profile_id=p.get("id", ""),
                        ssid=p.get("ssid", ""), bssid=p.get("bssid", ""),
                        simulated_bssid=p.get("simulated_bssid", ""),
                        channel=str(p.get("channel", "")), kind=self.kind,
                        started_at_ms=self.started_ms, finished_at_ms=self.finished_ms,
                        kismet_restored=self.restored,
                        executor_running=self.proc is not None and self.proc.poll() is None)

    def request(self, doc):
        action = doc.get("action")
        owner = doc.get("phone_id")
        if not isinstance(owner, str) or not (1 <= len(owner) <= 128):
            return dict(accepted=False, phase="refused", reason="invalid_owner")
        with self.lock:
            if action in ("check", "start"):
                observation = doc.get("observed")
                if not valid_observation(observation):
                    return dict(accepted=False, phase="refused", reason="stale_observation")
                profile = profile_for(doc.get("profile_id", ""), observation["bssid"],
                                      observation["ssid"], observation["channel"])
                kind = doc.get("kind", "ssid_lab")
                if profile is None or kind not in profile["allowed_tests"]:
                    return dict(accepted=False, phase="refused", reason="not_authorized_lab_target")
                if action == "check":
                    old = self.profile
                    self.profile = profile
                    response = self.status()
                    self.profile = old
                    response["phase"] = "available" if self.phase not in ("preparing", "running", "stopping", "restoring") else "busy"
                    response["accepted"] = response["phase"] == "available"
                    return response
                if self.thread is not None and self.thread.is_alive():
                    return dict(accepted=False, phase="busy", reason="another_lab_session")
                if PAUSE_MARKER.exists():
                    return dict(accepted=False, phase="refused", reason="monitor_already_paused")
                if not Path(MDK4).is_file():
                    return dict(accepted=False, phase="refused", reason="mdk4_not_installed")
                try:
                    radio_identity()
                except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
                    return dict(accepted=False, phase="refused", reason="radio_preflight_failed")
                self.session = uuid4().hex
                self.owner = owner
                self.profile = profile
                self.kind = kind
                self.phase = "preparing"
                self.reason = ""
                self.started_ms = 0
                self.finished_ms = 0
                self.restored = False
                self.deadline = time.monotonic() + LEASE_SECONDS
                self.hard_deadline = time.monotonic() + HARD_SECONDS
                self.stop_event.clear()
                self.thread = threading.Thread(target=self.worker, name="radio-lab-worker", daemon=True)
                self.thread.start()
                return self.status()
            if action == "status":
                if self.owner and owner != self.owner:
                    return dict(accepted=False, phase="refused", reason="not_session_owner")
                return self.status()
            if doc.get("session_id") != self.session or not self.session or owner != self.owner:
                return dict(accepted=False, phase="refused", reason="session_mismatch")
            if action == "renew":
                if self.phase not in ("preparing", "running") or time.monotonic() >= self.hard_deadline:
                    return dict(accepted=False, phase="refused", reason="session_not_renewable")
                self.deadline = time.monotonic() + LEASE_SECONDS
                return self.status()
            if action == "stop":
                self.stop_event.set()
                if self.phase in ("preparing", "running"):
                    self.phase = "stopping"
                return self.status()
            return dict(accepted=False, phase="refused", reason="unsupported_action")

    def worker(self):
        own_marker = False
        vif_created = False
        radio = None
        stopped_reason = "ended"
        try:
            radio = radio_identity()
            with kismet_operation():
                if PAUSE_MARKER.exists():
                    raise RuntimeError("radio_already_claimed")
                PAUSE_MARKER.write_text(json.dumps({"owner": "radio_lab", "session_id": self.session}))
                own_marker = True
            until = time.monotonic() + 24
            while time.monotonic() < until:
                if self.stop_event.is_set() or time.monotonic() > self.deadline:
                    raise RuntimeError("session_cancelled")
                if read_json(MONITOR).get("state") == "paused":
                    break
                time.sleep(0.3)
            else:
                raise RuntimeError("kismet_release_timeout")
            if radio_identity() != radio:
                raise RuntimeError("radio_identity_changed")
            if Path("/sys/class/net/" + LAB_IFACE).exists():
                raise RuntimeError("lab_interface_already_exists")
            run_checked(IW, "dev", MONITOR_INTERFACE, "interface", "add", LAB_IFACE, "type", "monitor")
            vif_created = True
            run_checked(IP, "link", "set", LAB_IFACE, "up")
            run_checked(IW, "dev", LAB_IFACE, "set", "channel", str(self.profile["channel"]))
            if self.kind == "probe":
                argv = [MDK4, LAB_IFACE, "p", "-e", self.profile["ssid"],
                        "-t", self.profile["bssid"], "-s", "1"]
            else:
                # One whitelisted fake identity, 1 frame/s. Never use MDK4 defaults.
                fake = RUN / "lab-ap.txt"
                fake.write_text(self.profile["simulated_bssid"] + " " + self.profile["ssid"] + "\n")
                os.chmod(fake, 0o600)
                argv = [MDK4, LAB_IFACE, "b", "-v", str(fake), "-t", "0",
                        "-w", "a", "-c", str(self.profile["channel"]), "-s", "1"]
            proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL, start_new_session=True, close_fds=True)
            with self.lock:
                self.proc = proc
                self.started_ms = int(time.time() * 1000)
                self.phase = "running"
            while not self.stop_event.wait(0.4):
                if proc.poll() is not None:
                    stopped_reason = "mdk4_exited"
                    break
                if time.monotonic() >= self.deadline:
                    stopped_reason = "phone_lease_expired"
                    break
                if time.monotonic() >= self.hard_deadline:
                    stopped_reason = "hard_time_limit"
                    break
                if radio_identity() != radio:
                    stopped_reason = "radio_identity_changed"
                    break
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as e:
            stopped_reason = str(e)[:96]
        finally:
            with self.lock:
                self.phase = "restoring"
                self.reason = stopped_reason
            proc = self.proc
            if proc is not None and proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                    proc.wait(timeout=2)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    try:
                        proc.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        pass
            with self.lock:
                self.proc = None
            if vif_created:
                try:
                    run_checked(IW, "dev", LAB_IFACE, "del")
                except (OSError, subprocess.SubprocessError):
                    stopped_reason = "lab_interface_cleanup_failed"
            (RUN / "lab-ap.txt").unlink(missing_ok=True)
            if own_marker:
                try:
                    with kismet_operation():
                        if read_json(PAUSE_MARKER).get("session_id") == self.session:
                            PAUSE_MARKER.unlink(missing_ok=True)
                except OSError:
                    stopped_reason = "monitor_resume_failed"
            restored = False
            until = time.monotonic() + 33
            while time.monotonic() < until:
                if read_json(MONITOR).get("state") == "ready":
                    restored = True
                    break
                time.sleep(0.5)
            with self.lock:
                self.finished_ms = int(time.time() * 1000)
                self.restored = restored
                self.phase = "finished" if restored else "degraded"
                self.reason = stopped_reason if restored else "monitor_not_restored:" + stopped_reason


def main():
    RUN.mkdir(mode=0o770, parents=True, exist_ok=True)
    SOCKET.unlink(missing_ok=True)
    lab = Lab()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
        server.bind(str(SOCKET))
        os.chmod(SOCKET, 0o660)
        server.listen(4)
        server.settimeout(0.5)
        while True:
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            with client:
                client.settimeout(1.0)
                try:
                    request = client.recv(4096)
                    if not request or len(request) >= 4096:
                        continue
                    result = lab.request(json.loads(request))
                except (ValueError, TypeError, KeyError):
                    result = dict(accepted=False, phase="refused", reason="invalid_request")
                client.sendall((json.dumps(result, separators=(",", ":")) + "\n").encode())


if __name__ == "__main__":
    main()
