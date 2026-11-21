"""Install the opt-in local file replay and Bluetooth scan units on the Pi."""

import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent


def run(*args):
    subprocess.run(args, check=True)


def setup():
    if os.geteuid() != 0:
        raise SystemExit("Run setup as root.")
    src = HERE.parents[1] / "mcp_server"
    dst = Path("/usr/local/lib/piagent-sources/raspberry/mcp_server")
    if not Path("/etc/kismet/piagent.conf").is_file():
        raise SystemExit("Configure the PiAgent Kismet backend first.")
    subprocess.run(["systemd-sysusers", "-"], input=(
        'g piagent-captures -\ng kismet -\nu piagent-bt-scan - "PocketNet bounded HCI scan"\n'
    ), text=True, check=True)
    run("install", "-d", "-m", "0755", dst, "/etc/piagent-sources")
    run("install", "-d", "-m", "0750", "-o", "root", "-g", "piagent-captures", "/var/lib/piagent-captures")
    for file in ("__init__.py", "file_sources.py", "source_control.py", "kismet_adapter.py", "capabilities.py"):
        run("install", "-m", "0644", src / file, dst / file)
    for unit in ("piagent-replay.socket", "piagent-replay.service", "piagent-bluetooth-scan.service"):
        run("install", "-m", "0644", HERE / unit, Path("/etc/systemd/system") / unit)
    for unit in ("piagent-mcp", "piagent-kismet"):
        path = Path(f"/etc/systemd/system/{unit}.service.d/captures.conf")
        path.parent.mkdir(mode=0o755, exist_ok=True)
        path.write_text("[Service]\nSupplementaryGroups=piagent-captures\n")
    run("systemctl", "daemon-reload")
    run("systemctl", "enable", "--now", "piagent-replay.socket")
    print("Replay socket installed. Restart piagent-kismet and piagent-mcp to apply group membership.")


if __name__ == "__main__":
    setup()
