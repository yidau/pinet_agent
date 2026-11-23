"""Provision the explicitly assigned USB radio for PocketNet's Kismet manager."""

import argparse
import base64
from dataclasses import asdict
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from urllib.parse import urlsplit
from uuid import uuid4

from configure import ENV, HERE, STATE, api, create_key, read_fields, run, write_private


ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT))
from raspberry.wireless.wireless_manager import (  # noqa: E402
    HOSTAPD, MONITOR_INTERFACE, NET, MonitorConfig, matches_config, usb_radio,
)


CONFIG = ENV.parent / "monitor.json"
KEY = ENV.parent / "monitor.key"
KISMET_CONFIG = Path("/etc/kismet/piagent.conf")
LINK = Path("/etc/systemd/network/10-piagent-monitor.link")
MONITOR_UNIT = "piagent-wireless-manager.service"
KISMET_DROP_IN = Path("/etc/systemd/system/piagent-kismet.service.d/monitor-helper.conf")
DROP_IN_TEXT = """[Service]
SupplementaryGroups=kismet
NoNewPrivileges=no
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_SETUID CAP_SETGID
"""


def check_capture_helper():
    binary = Path("/usr/bin/kismet_cap_linux_wifi")
    try:
        mode = binary.stat()
    except FileNotFoundError:
        raise SystemExit("Install the Linux Wi-Fi capture helper that matches the installed Kismet core.") from None
    if not stat.S_ISREG(mode.st_mode) or mode.st_uid != 0 or mode.st_mode & 0o022:
        raise SystemExit("The packaged Wi-Fi capture helper is not trusted.")
    if not mode.st_mode & stat.S_ISUID:
        try:
            caps = subprocess.check_output(["getcap", binary], text=True, timeout=4)
        except (OSError, subprocess.SubprocessError):
            caps = ""
        if not all(capability in caps for capability in ("cap_net_admin", "cap_net_raw")):
            raise SystemExit("Install the packaged Wi-Fi helper with its documented restricted privileges.")


def local_credentials():
    fields = read_fields(ENV)
    url = urlsplit(fields["PIAGENT_KISMET_URL"])
    if (url.scheme != "http" or url.hostname != "127.0.0.1" or url.username is not None
            or url.password is not None or url.path not in ("", "/") or url.query or url.fragment):
        raise SystemExit("Expected the existing PiAgent loopback Kismet configuration.")
    auth = read_fields(STATE / ".kismet" / "kismet_httpd.conf")
    login = (auth["httpd_username"] + ":" + auth["httpd_password"]).encode()
    return url.port, {"Authorization": "Basic " + base64.b64encode(login).decode(),
                      "Content-Type": "application/json"}


def detect_usb(interface, vendor, product, driver, port):
    if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,14}", interface):
        raise SystemExit("Select a valid USB wireless interface name.")
    ap = read_fields(HOSTAPD).get("interface", "")
    if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,14}", ap):
        raise SystemExit("Cannot safely identify the management hotspot.")
    radio = usb_radio(NET / interface)
    if radio.phy == (NET / ap / "phy80211").resolve(strict=True):
        raise SystemExit("The selected device shares the management hotspot's radio.")
    kismet_port, headers = local_credentials()
    previous = json.loads(CONFIG.read_text(encoding="utf-8")) if CONFIG.exists() else {}
    config = MonitorConfig(vendor.lower(), product.lower(), port, driver,
                           previous.get("datasource_uuid", str(uuid4())), kismet_port)
    if not matches_config(radio, config):
        raise SystemExit("The specified VID/PID, port or driver does not match the selected device.")
    if previous and previous != asdict(config):
        raise SystemExit("An existing monitor role differs. Remove that assignment while the manager is stopped before replacing it.")
    if interface != MONITOR_INTERFACE and (NET / MONITOR_INTERFACE).exists():
        raise SystemExit(f"The reserved name {MONITOR_INTERFACE} is already in use.")
    properties = subprocess.check_output(["udevadm", "info", "--query=property", "--path", NET / interface],
                                         text=True, timeout=4)
    fields = dict(line.split("=", 1) for line in properties.splitlines() if "=" in line)
    path = fields.get("ID_PATH", "")
    if (not re.fullmatch(r"[A-Za-z0-9_.:-]{1,240}", path) or fields.get("ID_NET_DRIVER") != driver
            or fields.get("ID_BUS") != "usb" or fields.get("ID_VENDOR_ID") != config.vendor
            or fields.get("ID_MODEL_ID") != config.product):
        raise SystemExit("udev did not confirm the exact path, VID/PID and driver for the selected USB device.")
    return config, path, headers


def install(*args):
    run("install", *args)


def setup(args):
    if os.geteuid() != 0:
        raise SystemExit("Run monitor provisioning with sudo.")
    check_capture_helper()
    config, link_path, headers = detect_usb(args.interface, args.vendor, args.product, args.driver, args.port)
    kismet_settings = read_fields(KISMET_CONFIG)
    if (kismet_settings.get("enable_logging") != "false"
            or kismet_settings.get("httpd_bind_address") != "127.0.0.1"
            or kismet_settings.get("httpd_allow_auth_view") != "false"
            or kismet_settings.get("remote_capture_enabled") != "false"):
        raise SystemExit("Expected the existing log-free, loopback-only PiAgent Kismet configuration.")
    key = KEY.read_text(encoding="ascii").strip() if KEY.exists() else ""
    auth_resource = "/auth/apikey/list.json"
    if not key or api(config.kismet_port, auth_resource, {"Cookie": "KISMET=" + key})[0] != 200:
        key = create_key(config.kismet_port, headers, "admin")
        if api(config.kismet_port, auth_resource, {"Cookie": "KISMET=" + key})[0] != 200:
            raise SystemExit("The dedicated Kismet credential could not authorize datasource management.")
    subprocess.run(["systemd-sysusers", "-"], text=True, check=True,
                   input='g kismet -\nu piagent-wireless - "PocketNet wireless datasource manager"\n')
    modules = Path("/usr/local/lib/piagent-wireless/raspberry/wireless")
    install("-d", "-m", "0755", modules)
    for file in ("__init__.py", "kismet_adapter.py", "wireless_manager.py"):
        install("-m", "0644", ROOT / "raspberry/wireless" / file, modules / file)
    install("-m", "0644", HERE / MONITOR_UNIT, Path("/etc/systemd/system") / MONITOR_UNIT)
    link = (f"[Match]\nPath={link_path}\nDriver={config.driver}\n"
            f"Property=ID_BUS=usb ID_VENDOR_ID={config.vendor} ID_MODEL_ID={config.product}\n"
            f"\n[Link]\nNamePolicy=\nName={MONITOR_INTERFACE}\n")
    for path, content in (
        (LINK, link),
        (KISMET_DROP_IN, DROP_IN_TEXT),
    ):
        path.parent.mkdir(mode=0o755, exist_ok=True, parents=True)
        write_private(path, content)
        path.chmod(0o644)
    write_private(CONFIG, json.dumps(asdict(config)) + "\n")
    write_private(KEY, key + "\n")
    run("systemctl", "daemon-reload")
    print(f"Installed {MONITOR_UNIT}. Apply the USB naming rule and start the role using the deployment instructions.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interface", required=True, help="Current interface of the selected USB adapter.")
    parser.add_argument("--vendor", required=True, help="Four hexadecimal digits from idVendor.")
    parser.add_argument("--product", required=True, help="Four hexadecimal digits from idProduct.")
    parser.add_argument("--port", required=True, help="Exact kernel USB device name, e.g. 1-1.2.")
    parser.add_argument("--driver", required=True, help="Driver name confirmed for this radio.")
    try:
        setup(parser.parse_args())
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"Could not provision the USB monitor: {type(exc).__name__}.") from None
