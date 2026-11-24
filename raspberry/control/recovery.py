"""Accept one checked action on the locally activated control socket."""

import fcntl
import json
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys
import tempfile
import time

from raspberry.config.kismet.configure import ENV, read_fields
from raspberry.wireless.wireless_manager import (
    DESIRED_PROFILE, FIELD, PROFILES, MonitorApi, MonitorConfig, MonitorManager,
    Unavailable, actual_profile, select_radio,
)
from raspberry.wireless.kismet_adapter import KismetError


CONTROL = Path("/run/pocketnet-control")
CONFIG = Path("/etc/piagent-kismet/monitor.json")
MONITOR = Path("/run/piagent-wireless/monitor.json")
ACTIONS = {*PROFILES, "pressure_light", "monitor", "check_hotspot", "hotspot", "ble"}


def read_object(path):
    try:
        with path.open(encoding="utf-8") as handle:
            contents = handle.read(8193)
        value = json.loads(contents) if len(contents) <= 8192 else None
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def replace_json(path, body, *, mode=0o644, owner=None):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, encoding="utf-8", delete=False) as handle:
        temporary = Path(handle.name)
        try:
            json.dump(body, handle, separators=(",", ":"))
            handle.flush()
            os.fchmod(handle.fileno(), mode)
            if owner is not None:
                os.fchown(handle.fileno(), owner.pw_uid, owner.pw_gid)
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def reply(status, reason=""):
    print(json.dumps({"status": status, "reason": reason}), flush=True)


def command(path, *args):
    return subprocess.run([path, *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, timeout=4, check=False)


def active(unit):
    return command("/usr/bin/systemctl", "is-active", "--quiet", unit).returncode == 0


def restart(*units):
    return command("/usr/bin/systemctl", "--no-block", "restart", *units).returncode == 0


def hotspot_healthy():
    ping = command("/usr/sbin/hostapd_cli", "-i", "wlan0", "ping")
    return ping.returncode == 0 and ping.stdout.strip() == "PONG" and active("piagent-dhcp.service")


def ble_healthy():
    controller = command("/usr/bin/bluetoothctl", "show")
    return (controller.returncode == 0 and re.search(r"(?m)^\s*Powered: yes\s*$", controller.stdout)
            and active("piagent-ble-time-sync.service"))


def wait_for(predicate, seconds=21):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.5)
    return False


def monitor_access():
    config = MonitorConfig(**read_object(CONFIG))
    radio = select_radio(config)
    fields = read_fields(ENV)
    api = MonitorApi(f"http://127.0.0.1:{config.kismet_port}", fields["PIAGENT_KISMET_API_KEY"])
    manager = MonitorManager(config, api)
    sources = api.list_sources()
    owned = manager.owned_source(sources)
    if any(source is not owned for source in sources):
        raise Unavailable("unmanaged_kismet_source")
    if owned and owned.get(FIELD + "paused") in (True, 1):
        raise Unavailable("monitor_source_paused")
    return config, radio, owned


def prepare_profile(profile):
    pd = pwd.getpwnam("piagent-wireless")
    replace_json(DESIRED_PROFILE, {"profile": profile}, mode=0o600, owner=pd)


def rebuild(profile, state, config, radio):
    # Recheck ownership and radio identity just before changing the instance.
    current_config, current_radio, _ = monitor_access()
    if current_config != config or current_radio != radio:
        raise Unavailable("monitor_identity_changed")
    prepare_profile(profile)
    state["recovery_phase"] = "recovering"
    replace_json(CONTROL / "state.json", state)
    before_restart = time.monotonic_ns()
    if not restart("piagent-kismet.service"):
        return False
    state["recovery_phase"] = "verifying"
    replace_json(CONTROL / "state.json", state)

    def confirmed():
        status = read_object(MONITOR)
        if (status.get("state") != "ready" or status.get("actual_profile") != profile
                or status.get("datasource_uuid") != config.datasource_uuid
                or status.get("boottime_ns", 0) <= before_restart):
            return False
        try:
            checked, present, source = monitor_access()
            return checked == config and present == radio and source and actual_profile(source) == profile
        except (OSError, KeyError, TypeError, ValueError, KismetError, Unavailable, subprocess.SubprocessError):
            return False

    return wait_for(confirmed, seconds=33)


def process(action, request_id, state):
    profile_change = action in PROFILES or action == "pressure_light"
    if profile_change or action == "monitor":
        target = "light" if action == "pressure_light" else action
        config, radio, owned = monitor_access()
        existing = actual_profile(owned) if owned else None
        if action == "monitor":
            target = existing or "light"
        if profile_change:
            state.update(requested=target, phase="switching", pressure_forced=action == "pressure_light")
        state["component"] = "monitor"
        if (owned and existing == target and owned.get(FIELD + "running") in (True, 1)
                and owned.get(FIELD + "error") in (False, 0) and read_object(MONITOR).get("state") == "ready"):
            if profile_change:
                state["phase"] = "ready"
            return "ready", ""
        if rebuild(target, state, config, radio):
            if profile_change:
                state["phase"] = "ready"
            return "ready", ""
        if profile_change:
            state["phase"] = "failed"
            if target != "light" and rebuild("light", state, config, radio):
                state["phase"] = "rolled_back"
                return "ready", "profile_rolled_back_to_light"
        return "failed", "monitor_not_verified"
    if action in ("check_hotspot", "hotspot"):
        state["component"] = "hotspot"
        if hotspot_healthy():
            return "ready", ""
        if action == "check_hotspot":
            return "failed", "hotspot_restart_requires_confirmation"
        state["recovery_phase"] = "recovering"
        replace_json(CONTROL / "state.json", state)
        if restart("piagent-hotspot.service", "piagent-dhcp.service", "piagent-telemetry.service") and wait_for(hotspot_healthy):
            return "ready", ""
        return "failed", "hotspot_not_verified"
    state["component"] = "ble"
    if ble_healthy():
        return "ready", ""
    state["recovery_phase"] = "recovering"
    replace_json(CONTROL / "state.json", state)
    if restart("bluetooth.service", "piagent-ble-time-sync.service") and wait_for(ble_healthy):
        return "ready", ""
    return "failed", "bluetooth_not_verified"


def handle(action, request_id, path):
    with (path / "operation.lock").open("a", encoding="ascii") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return reply("busy", "another_recovery_is_running")
        state = read_object(path / "state.json")
        recent = state.get("recent", {})
        if request_id in recent:
            return reply("accepted", "request_already_processed")
        now = time.monotonic()
        if now - state.get("issued_at", -60) < 8 and action != "pressure_light":
            return reply("busy", "control_cooldown")
        if action in PROFILES or action in ("pressure_light", "monitor"):
            try:
                monitor_access()
            except Unavailable as exc:
                return reply("refused", str(exc))
            except (OSError, KeyError, TypeError, ValueError, KismetError, subprocess.SubprocessError):
                return reply("refused", "monitor_preflight_failed")
        recent = dict(list(recent.items())[-15:])
        recent[request_id] = now
        component = "ble" if action == "ble" else ("hotspot" if action in ("hotspot", "check_hotspot") else "monitor")
        state.update(recent=recent, issued_at=now, request_id=request_id, recovery_phase="checking", component=component)
        replace_json(path / "state.json", state)
        reply("accepted")
        try:
            phase, reason = process(action, request_id, state)
        except Unavailable as exc:
            phase, reason = "failed", str(exc)
        except (OSError, KeyError, TypeError, ValueError, KismetError, subprocess.SubprocessError):
            phase, reason = "failed", "control_operation_failed"
        if phase == "failed" and state.get("phase") == "switching":
            state["phase"] = "failed"
        state.update(recovery_phase=phase, reason=reason)
        replace_json(path / "state.json", state)


def main():
    try:
        line = sys.stdin.buffer.readline(512)
        if not line.endswith(b"\n"):
            return reply("refused", "invalid_control_request")
        data = json.loads(line)
        action, request_id = data["action"], data["request_id"]
        if not isinstance(action, str) or action not in ACTIONS or not isinstance(request_id, str):
            return reply("unsupported", "unknown_action")
        if not re.fullmatch("[a-f0-9]{32}", request_id):
            return reply("refused", "invalid_request_id")
        handle(action, request_id, CONTROL)
    except (OSError, KeyError, ValueError, TypeError):
        return reply("refused", "invalid_control_request")


if __name__ == "__main__":
    main()
