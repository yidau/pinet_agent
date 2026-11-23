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


HERE = Path(__file__).resolve().parent
STATE = Path("/var/lib/piagent-kismet")
ENV = Path("/run/piagent-kismet/client.env")
MONITOR_CONFIG = Path("/etc/piagent-kismet/monitor.json")
MONITOR_KEY = Path("/run/piagent-kismet/monitor.key")
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


def key_headers(port, key):
    return {"Cookie": f"KISMET={key}; KISMET_{port}={key}"}


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


def install_service(port):
    config = Path("/etc/kismet/piagent.conf")
    config.write_text((HERE / "piagent.conf").read_text() + f"\nhttpd_port={port}\n")
    run("install", "-m", "0644", HERE / UNIT, Path("/etc/systemd/system") / UNIT)
    run("systemctl", "daemon-reload")


def provision_api_keys(port, headers):
    """Recreate Kismet API keys when its volatile HTTP session DB is empty."""
    run("install", "-d", "-m", "0700", ENV.parent)
    key = read_fields(ENV).get("PIAGENT_KISMET_API_KEY", "") if ENV.exists() else ""
    if not key or api(port, "/datasource/all_sources.json", key_headers(port, key))[0] != 200:
        key = create_key(port, headers, "readonly")
        if api(port, "/datasource/all_sources.json", key_headers(port, key))[0] != 200:
            raise SystemExit("The new readonly Kismet credential failed verification.")
    contents = f"PIAGENT_KISMET_URL=http://127.0.0.1:{port}\nPIAGENT_KISMET_API_KEY={key}\n"
    if not ENV.exists() or ENV.read_text() != contents:
        write_private(ENV, contents)

    # The datasource manager needs an admin token only when a USB monitor radio
    # has been assigned. The token lives in /run alongside the volatile Kismet DB.
    if MONITOR_CONFIG.exists():
        admin_key = MONITOR_KEY.read_text(encoding="ascii").strip() if MONITOR_KEY.exists() else ""
        if not admin_key or api(port, "/auth/apikey/list.json", key_headers(port, admin_key))[0] != 200:
            admin_key = create_key(port, headers, "admin")
            if api(port, "/auth/apikey/list.json", key_headers(port, admin_key))[0] != 200:
                raise SystemExit("The new Kismet datasource-management credential failed verification.")
        if not MONITOR_KEY.exists() or MONITOR_KEY.read_text(encoding="ascii").strip() != admin_key:
            write_private(MONITOR_KEY, admin_key + "\n")


def wait_for_api(port, headers):
    for attempt in range(25):
        try:
            status, _ = api(port, "/system/status.json", headers)
        except (OSError, http.client.HTTPException):
            status = 0
        if status == 200:
            return
        if status in (401, 403) or attempt == 24:
            raise SystemExit(f"Kismet startup or local authentication failed (HTTP {status}). See journalctl -u {UNIT}.")
        time.sleep(0.4)


def provision_only(port):
    """Refresh volatile Kismet API credentials without restarting Kismet."""
    auth = STATE / ".kismet" / "kismet_httpd.conf"
    if not auth.is_file():
        raise SystemExit("Persistent Kismet authentication configuration is missing.")
    fields = read_fields(auth)
    login = (fields["httpd_username"] + ":" + fields["httpd_password"]).encode()
    headers = {"Authorization": "Basic " + base64.b64encode(login).decode(),
               "Content-Type": "application/json"}
    wait_for_api(port, headers)
    provision_api_keys(port, headers)


def setup(port, *, runtime_only=False):
    import pwd

    if not Path("/usr/bin/kismet").is_file():
        raise SystemExit("Install kismet-core first.")
    if not 1024 <= port <= 65535:
        raise SystemExit("Choose an unprivileged HTTP port between 1024 and 65535.")
    subprocess.run(["systemd-sysusers", "-"], text=True, check=True,
                   input='u piagent-kismet - "PocketNet Kismet" /var/lib/piagent-kismet\n')
    owner = pwd.getpwnam("piagent-kismet")
    auth = STATE / ".kismet" / "kismet_httpd.conf"
    for directory in (STATE, auth.parent):
        run("install", "-d", "-m", "0700", "-o", owner.pw_name, "-g", owner.pw_name, directory)
    if not auth.exists():
        write_private(auth, f"httpd_username=piagent-admin\nhttpd_password={secrets.token_hex(32)}\n", owner)
    run("install", "-d", "-m", "0700", ENV.parent)
    if not runtime_only:
        install_service(port)
    run("systemctl", "enable", UNIT)
    run("systemctl", "restart", UNIT)

    auth_fields = read_fields(auth)
    login = (auth_fields["httpd_username"] + ":" + auth_fields["httpd_password"]).encode()
    headers = {"Authorization": "Basic " + base64.b64encode(login).decode(),
               "Content-Type": "application/json"}
    wait_for_api(port, headers)
    provision_api_keys(port, headers)
    run("systemctl", "daemon-reload")
    print(f"Kismet ready on loopback port {port}. The C++ telemetry service reads the readonly Kismet credentials from its environment file.")


if __name__ == "__main__":
    if os.geteuid() != 0:
        raise SystemExit("Run provisioning with sudo.")
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, help="Local Kismet port (defaults to the installed package configuration).")
    parser.add_argument("--runtime-only", action="store_true", help="Use the image's preinstalled unit and configuration.")
    parser.add_argument("--provision-only", action="store_true",
                        help="Refresh volatile Kismet API keys without restarting Kismet.")
    args = parser.parse_args()
    config_path = Path("/etc/kismet/piagent.conf" if args.runtime_only else "/etc/kismet/kismet_httpd.conf")
    port = args.port if args.port is not None else int(read_fields(config_path)["httpd_port"])
    if args.provision_only:
        provision_only(port)
    else:
        setup(port, runtime_only=args.runtime_only)
