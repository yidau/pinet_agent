"""Install the local replay, phone controls and manually started radio units."""

import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent


def run(*args):
    subprocess.run(args, check=True)


def install_phone_directory(captures):
    import pwd

    group = captures.stat().st_gid
    username = subprocess.check_output(
        ["systemctl", "show", "--property=User", "--value", "piagent-mcp.service"], text=True
    ).strip()
    user = pwd.getpwnam(username)
    if not user.pw_uid:
        raise SystemExit("PiAgent MCP requires a non-root service user.")
    # Only the .phone subtree is writable by MCP. Never follow links in
    # its service-user-controlled subtree during a privileged reinstall.
    parent = os.open(captures, os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for name, mode in ((".phone", 0o2750), (".staging", 0o2700)):
            try:
                os.mkdir(name, 0o700, dir_fd=parent)
            except FileExistsError:
                pass
            child = os.open(name, os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
            os.close(parent)
            parent = child
            os.fchown(child, user.pw_uid, group)
            os.fchmod(child, mode)
    finally:
        os.close(parent)


def install_source_modules(src):
    working_directory = Path("/usr/local/lib/piagent-sources")
    package = working_directory / "raspberry"
    modules = package / "mcp_server"
    # Both the Bluetooth and replay units use this working directory under
    # dedicated UIDs. Normalize existing directories on upgrades as well.
    run("install", "-d", "-o", "root", "-g", "root", "-m", "0755", working_directory, package, modules)
    for file in ("__init__.py", "file_sources.py", "source_control.py", "kismet_adapter.py", "capabilities.py",
                 "phone_radio.py"):
        run("install", "-m", "0644", src / file, modules / file)


def setup():
    if os.geteuid() != 0:
        raise SystemExit("Run setup as root.")
    src = HERE.parents[1] / "mcp_server"
    if not Path("/etc/kismet/piagent.conf").is_file():
        raise SystemExit("Configure the PiAgent Kismet backend first.")
    subprocess.run(["systemd-sysusers", "-"], input=(
        'g piagent-captures -\ng piagent-phone -\ng kismet -\nu piagent-bt-scan - "PocketNet bounded HCI scan"\n'
    ), text=True, check=True)
    install_source_modules(src)
    run("install", "-d", "-m", "0755", "/etc/piagent-sources")
    run("install", "-d", "-m", "0750", "-o", "root", "-g", "piagent-captures", "/var/lib/piagent-captures")
    install_phone_directory(Path("/var/lib/piagent-captures"))
    for unit in ("piagent-replay.socket", "piagent-replay.service", "piagent-bluetooth-scan.service",
                 "piagent-phone-radio.socket", "piagent-phone-radio@.service"):
        run("install", "-m", "0644", HERE / unit, Path("/etc/systemd/system") / unit)
    for unit in ("piagent-mcp", "piagent-kismet"):
        path = Path(f"/etc/systemd/system/{unit}.service.d/captures.conf")
        path.parent.mkdir(mode=0o755, exist_ok=True)
        path.write_text("[Service]\nSupplementaryGroups=piagent-captures\n")
    Path("/etc/systemd/system/piagent-mcp.service.d/phone.conf").write_text(
        "[Service]\nSupplementaryGroups=piagent-phone\nReadWritePaths=/var/lib/piagent-captures/.phone\n"
    )
    run("systemctl", "daemon-reload")
    run("systemctl", "enable", "--now", "piagent-replay.socket", "piagent-phone-radio.socket")
    print("Installed operator sockets. Restart MCP to apply the handset controls.")


if __name__ == "__main__":
    setup()
