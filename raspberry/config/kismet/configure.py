"""Provision the local observation service after installing the signed kismet-core package."""

import argparse
import base64
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import tempfile
import time
import uuid


HERE = Path(__file__).resolve().parent
STATE = Path("/var/lib/piagent-kismet")
ENV = Path("/etc/piagent-kismet/client.env")
UNIT = "piagent-kismet.service"


def write_private(path, contents, owner=None):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as out:
        temp = Path(out.name)
        try:
            if owner:
                os.fchown(out.fileno(), owner.pw_uid, owner.pw_gid)
            out.write(contents)
            out.flush()
            os.replace(temp, path)
        finally:
            temp.unlink(missing_ok=True)


def read_fields(path):
    return dict(line.split("=", 1) for line in path.read_text().splitlines()
                if line and not line.lstrip().startswith("#") and "=" in line)


def run(*argv):
    subprocess.run(argv, check=True)


def api(port, path, headers, data=None):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
    try:
        method = "POST" if data is not None else "GET"
        connection.request(method, path, data, headers)
        reply = connection.getresponse()
        return reply.status, reply.read(65536)
    finally:
        connection.close()


def create_key(port, headers, role):
    payload = json.dumps({"name": "PocketNet-" + role + "-" + secrets.token_hex(6),
                          "role": role, "duration": 0})
    status, body = api(port, "/auth/apikey/generate.cmd", headers, payload)
    if status != 200 or not re.fullmatch(rb"[a-zA-Z0-9._~+/=-]+", body.strip()):
        raise SystemExit(f"Could not provision Kismet role {role} (HTTP {status}).")
    return body.strip().decode("ascii")


def configure_scan(port, headers, interface):
    scan_env = ENV.parent / "managed-scan.env"
    previous = read_fields(scan_env) if scan_env.exists() else {}
    source_uuid = previous.get("PIAGENT_SCAN_UUID") or str(uuid.uuid4())
    key = previous.get("PIAGENT_SCAN_KEY") or create_key(port, headers, "scanreport")
    write_private(scan_env, f"PIAGENT_SCAN_INTERFACE={interface}\nPIAGENT_SCAN_UUID={source_uuid}\n"
                  f"PIAGENT_SCAN_URL=http://127.0.0.1:{port}\nPIAGENT_SCAN_KEY={key}\n")
    working_directory = Path("/usr/lib/piagent-managed-scan")
    package = working_directory / "raspberry"
    modules = package / "mcp_server"
    # A prior installation can leave a root-only parent. The service must
    # enter its working directory and traverse both Python package directories.
    run("install", "-d", "-o", "root", "-g", "root", "-m", "0755", working_directory, package, modules)
    for filename in ("__init__.py", "kismet_adapter.py", "managed_scan.py"):
        run("install", "-m", "0644", HERE.parents[1] / "mcp_server" / filename, modules / filename)
    unit = "piagent-managed-scan@.service"
    run("install", "-m", "0644", HERE / unit, Path("/etc/systemd/system") / unit)


def setup(port, scan_interface):
    import pwd

    if not Path("/usr/bin/kismet").is_file():
        raise SystemExit("Install kismet-core first.")
    if not 1024 <= port <= 65535:
        raise SystemExit("Choose an unprivileged HTTP port between 1024 and 65535.")
    if not re.fullmatch(r"[a-zA-Z0-9_.-]{1,15}", scan_interface):
        raise SystemExit("Choose a valid Linux Wi-Fi interface name.")
    if not Path("/etc/systemd/system/piagent-mcp.service").is_file():
        raise SystemExit("Install the PiAgent MCP unit first.")
    subprocess.run(["systemd-sysusers", "-"], text=True, check=True,
                   input="u piagent-kismet - \"PocketNet Kismet\" /var/lib/piagent-kismet\n"
                         "u piagent-scan - \"PocketNet Wi-Fi reporter\" /nonexistent\n")
    owner = pwd.getpwnam("piagent-kismet")
    auth = STATE / ".kismet" / "kismet_httpd.conf"
    for directory in (STATE, auth.parent):
        run("install", "-d", "-m", "0700", "-o", owner.pw_name, "-g", owner.pw_name, directory)
    if not auth.exists():
        write_private(auth, f"httpd_username=piagent-admin\nhttpd_password={secrets.token_hex(32)}\n", owner)
    run("install", "-d", "-m", "0700", ENV.parent)
    config = Path("/etc/kismet/piagent.conf")
    config.write_text((HERE / "piagent.conf").read_text() + f"\nhttpd_port={port}\n")
    run("install", "-m", "0644", HERE / UNIT, Path("/etc/systemd/system") / UNIT)
    run("systemctl", "daemon-reload")
    run("systemctl", "enable", UNIT)
    run("systemctl", "restart", UNIT)

    auth_fields = read_fields(auth)
    login = (auth_fields["httpd_username"] + ":" + auth_fields["httpd_password"]).encode()
    headers = {"Authorization": "Basic " + base64.b64encode(login).decode(),
               "Content-Type": "application/json"}
    for attempt in range(25):
        try:
            status, _ = api(port, "/system/status.json", headers)
        except (OSError, http.client.HTTPException):
            status = 0
        if status == 200:
            break
        if status in (401, 403) or attempt == 24:
            raise SystemExit(f"Kismet startup or local authentication failed (HTTP {status}). See journalctl -u {UNIT}.")
        time.sleep(0.4)

    key = read_fields(ENV).get("PIAGENT_KISMET_API_KEY", "") if ENV.exists() else ""
    if not key or api(port, "/datasource/all_sources.json", {"Cookie": "KISMET=" + key})[0] != 200:
        key = create_key(port, headers, "readonly")
        if api(port, "/datasource/all_sources.json", {"Cookie": "KISMET=" + key})[0] != 200:
            raise SystemExit("The new readonly credential failed verification.")
    write_private(ENV, f"PIAGENT_KISMET_URL=http://127.0.0.1:{port}\nPIAGENT_KISMET_API_KEY={key}\n")
    configure_scan(port, headers, scan_interface)
    run("install", "-D", "-m", "0644", HERE / "mcp-kismet.conf",
        "/etc/systemd/system/piagent-mcp.service.d/kismet.conf")
    run("systemctl", "daemon-reload")
    print(f"Kismet ready on loopback port {port}. Restart piagent-mcp after installing its V0.7 modules.")


if __name__ == "__main__":
    if os.geteuid() != 0:
        raise SystemExit("Run provisioning with sudo.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, help="Local Kismet port (defaults to the installed package configuration).")
    parser.add_argument("--scan-interface", default="wlan0", help="Wi-Fi interface for manual scans.")
    args = parser.parse_args()
    port = args.port if args.port is not None else int(read_fields(Path("/etc/kismet/kismet_httpd.conf"))["httpd_port"])
    setup(port, args.scan_interface)
