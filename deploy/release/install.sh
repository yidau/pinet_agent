#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $EUID -ne 0 ]]; then
    echo "Run the PocketNet release installer as root" >&2
    exit 1
fi

exec python3 - "$@" <<'PYTHON'
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time


RELEASE = re.compile(r"[a-f0-9]{40}")
SHA256 = re.compile(r"[a-fA-F0-9]{64}")
TELEMETRY = "bin/piagent-telemetry"
RUNTIME_CONFIG = Path("raspberry/config/runtime")
PACKAGED_DIRS = {"bin", "raspberry"}
PACKAGED_FILES = {"install.sh", "manifest.json"}
REQUIRED_VERSION_FIELDS = (
    "python_version", "kismet_version", "protobuf_version", "grpc_version", "cpp_compiler_version",
)


def sha256(path):
    with path.open("rb") as source:
        digest = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
        return digest.hexdigest()


def unpack(archive, stage):
    seen = set()
    stage.mkdir()
    with tarfile.open(archive, "r:gz") as package:
        for member in package:
            name = PurePosixPath(member.name)
            if (name.is_absolute() or not name.parts or ".." in name.parts or "\\" in member.name
                    or name.as_posix() != member.name or name in seen
                    or name.parts[0] not in PACKAGED_DIRS | PACKAGED_FILES
                    or member.isdir() and name.parts[0] in PACKAGED_FILES
                    or member.isfile() and name.parts[0] in PACKAGED_FILES and len(name.parts) != 1
                    or not (member.isdir() or member.isfile())):
                raise ValueError(f"Unexpected release member: {member.name!r}")
            seen.add(name)
            destination = stage / name
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            with package.extractfile(member) as source, destination.open("xb") as target:
                shutil.copyfileobj(source, target)
            destination.chmod(0o755 if name.as_posix() in {TELEMETRY, "install.sh"} else 0o644)


def validate_payload(stage):
    manifest = json.loads((stage / "manifest.json").read_text())
    commit = manifest.get("git_commit")
    if (manifest.get("schema_version") != 1 or not isinstance(commit, str) or not RELEASE.fullmatch(commit)
            or manifest.get("version") != commit or manifest.get("architecture") != "arm64"
            or manifest.get("ubuntu_release") != "22.04" or manifest.get("build_type") != "Release"
            or not str(manifest.get("python_version", "")).startswith("3.12.")
            or any(not manifest.get(field) for field in REQUIRED_VERSION_FIELDS)):
        raise ValueError("Invalid PocketNet Ubuntu 22.04 ARM64 release manifest")
    hashes = {
        path.relative_to(stage).as_posix(): sha256(path)
        for path in sorted(stage.rglob("*"))
        if path.is_file() and path != stage / "manifest.json"
    }
    if hashes != manifest.get("files") or not {TELEMETRY, "install.sh"} <= hashes.keys():
        raise ValueError("Release file checksums do not match the manifest")
    with (stage / TELEMETRY).open("rb") as binary:
        header = binary.read(64)
    if (len(header) != 64 or header[:7] != b"\x7fELF\x02\x01\x01"
            or struct.unpack_from("<HH", header, 16) not in ((2, 183), (3, 183))):
        raise ValueError("Telemetry executable must be a Linux AArch64 ELF")
    return manifest


def validate_host(root, live, stage, manifest):
    os_release = {}
    for line in (root / "usr/lib/os-release").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            os_release[key] = value.strip('"')
    if os_release.get("ID") != "ubuntu" or os_release.get("VERSION_ID") != "22.04":
        raise ValueError("Release requires Ubuntu 22.04")
    if live:
        if os.uname().machine != "aarch64":
            raise ValueError("Release requires an ARM64 device")
        target_python = "/opt/pocketnet/python/bin/python3.12"
        python_version = subprocess.check_output([target_python, "--version"], text=True).strip()
        if python_version != f"Python {manifest['python_version']}":
            raise ValueError(f"Python runtime mismatch: {python_version}")
        libraries = subprocess.check_output(["ldd", str(stage / TELEMETRY)], text=True)
        if "not found" in libraries:
            raise ValueError("Telemetry executable has missing shared libraries")


def set_current(prefix, link):
    with tempfile.TemporaryDirectory(prefix=".current-", dir=prefix) as temp:
        staged_link = Path(temp) / "current"
        staged_link.symlink_to(link)
        os.replace(staged_link, prefix / "current")


def current_link(prefix):
    current = prefix / "current"
    if current.is_symlink():
        value = os.readlink(current)
        if not re.fullmatch(r"releases/[a-f0-9]{40}", value) or not (prefix / value).is_dir():
            raise ValueError("Unexpected PocketNet current symlink")
        return value
    if current.exists():
        raise ValueError("PocketNet current must be a release symlink")
    return None


def changed_units(before, after):
    changes = {file for file in before.keys() | after.keys() if before.get(file) != after.get(file)}
    time_common = bool(changes & {"raspberry/time_sync/protocol.py", "raspberry/time_sync/__init__.py"})
    wifi_helper = "raspberry/enrollment/wifi_helper.py"
    units = []
    if TELEMETRY in changes:
        units.append("piagent-telemetry.service")
    if time_common or "raspberry/time_sync/clock_helper.py" in changes:
        units.append("piagent-clock.service")
    if time_common or "raspberry/time_sync/ble_server.py" in changes or any(
        file.startswith("raspberry/enrollment/") and file != wifi_helper for file in changes
    ):
        units.append("piagent-ble-time-sync.service")
    if wifi_helper in changes:
        units.append("piagent-enrollment-wifi.service")
    if "raspberry/config/kismet/configure.py" in changes:
        units.append("piagent-kismet-provision.service")
    if "raspberry/config/runtime/prepare-hotspot.py" in changes:
        units.append("piagent-hotspot.service")
    if any(file.startswith("raspberry/active_lab/") for file in changes):
        units.append("piagent-active-lab.service")
    if "raspberry/config/kismet/configure_monitor.py" in changes or any(
        file.startswith("raspberry/wireless/") for file in changes
    ):
        units.append("piagent-wireless-manager.service")
    return units


def active(unit):
    return subprocess.run(["systemctl", "is-active", "--quiet", unit], timeout=10).returncode == 0


def restart(units):
    if units:
        subprocess.run(["systemctl", "restart", *units], check=True, timeout=90)
        time.sleep(2)
        inactive = [unit for unit in units if not active(unit)]
        if inactive:
            raise RuntimeError("Services did not stay active: " + ", ".join(inactive))


def place_updater(prefix, source):
    deploy = prefix / "deploy"
    deploy.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".updater-", dir=deploy) as temp:
        staged_updater = Path(temp) / "install-release.sh"
        shutil.copyfile(source, staged_updater)
        staged_updater.chmod(0o755)
        os.replace(staged_updater, deploy / staged_updater.name)


def managed_configuration(root, release):
    assets = release / RUNTIME_CONFIG
    if not assets.is_dir():
        return {}
    settings = {
        "etc/systemd/system/piagent-telemetry.service": (assets / "piagent-telemetry.service").read_bytes(),
        "etc/systemd/system/piagent-ble-time-sync.service.d/90-pocketnet-image.conf":
            (assets / "piagent-ble-time-sync.conf").read_bytes(),
        "etc/systemd/system/piagent-telemetry.service.d/90-pocketnet-image.conf":
            (assets / "piagent-telemetry.conf").read_bytes(),
        "etc/systemd/system/piagent-kismet.service":
            (release / "raspberry/config/kismet/piagent-kismet.service").read_bytes(),
        "etc/systemd/system/piagent-kismet-provision.service":
            (release / "raspberry/config/kismet/piagent-kismet-provision.service").read_bytes(),
        "etc/systemd/system/piagent-wireless-manager.service":
            (release / "raspberry/config/kismet/piagent-wireless-manager.service").read_bytes(),
        "etc/piagent-kismet/client.env": None,
        "etc/piagent-kismet/monitor.key": None,
        "etc/systemd/system/tmp.mount": (assets / "tmp.mount").read_bytes(),
        "etc/systemd/journald.conf.d/pocketnet.conf": (assets / "pocketnet-journald.conf").read_bytes(),
        "etc/default/zramswap": (assets / "zramswap").read_bytes(),
        "etc/systemd/system/swapfile.swap": "/dev/null",
        "etc/systemd/system/dphys-swapfile.service": "/dev/null",
    }
    # New releases carry the management hotspot units as well as telemetry.
    # Keep the enablement links in the same rollback transaction as the units;
    # older release archives without these assets remain installable.
    for unit in ("piagent-hotspot.service", "piagent-dhcp.service"):
        asset = assets / unit
        if asset.is_file():
            settings[f"etc/systemd/system/{unit}"] = asset.read_bytes()
            settings[f"etc/systemd/system/multi-user.target.wants/{unit}"] = f"../{unit}"
    socket = assets / "piagent-control.socket"
    control_assets = {
        "etc/systemd/system/piagent-control.socket": socket,
        "etc/systemd/system/piagent-control@.service": assets / "piagent-control@.service",
        "etc/sysusers.d/piagent-control.conf": assets / "piagent-control.sysusers.conf",
    }
    for path, asset in control_assets.items():
        settings[path] = asset.read_bytes() if socket.is_file() else None
    settings["etc/systemd/system/sockets.target.wants/piagent-control.socket"] = (
        "../piagent-control.socket" if socket.is_file() else None)
    lab_unit = assets / "piagent-active-lab.service"
    settings["etc/systemd/system/piagent-active-lab.service"] = (
        lab_unit.read_bytes() if lab_unit.is_file() else None)
    settings["etc/systemd/system/multi-user.target.wants/piagent-active-lab.service"] = (
        "../piagent-active-lab.service" if lab_unit.is_file() else None)
    kismet = "etc/kismet/piagent.conf"
    template = (release / "raspberry/config/kismet/piagent.conf").read_bytes()
    if (root / kismet).is_file():
        keys = {b"httpd_auth_file", b"httpd_session_db", b"enable_logging"}
        current = (root / kismet).read_bytes().splitlines()
        lines = [line for line in current if line.split(b"=", 1)[0].strip() not in keys]
        lines.extend(line for line in template.splitlines() if line.partition(b"=")[0] in keys)
        settings[kismet] = b"\n".join(lines) + b"\n"
    else:
        settings[kismet] = template + b"\nhttpd_port=2501\n"

    fstab = root / "etc/fstab"
    if fstab.is_file():
        for line in fstab.read_text().splitlines():
            fields = line.split("#", 1)[0].split()
            if fields[1:2] == ["/tmp"] and fields[2:3] != ["tmpfs"]:
                raise ValueError("Resolve the existing fstab /tmp entry before applying the PocketNet mount")
    settings["etc/systemd/system/local-fs.target.wants/tmp.mount"] = "../tmp.mount"

    # Remove existing fstab swap entries so systemd cannot reactivate SD swap.
    fstab = root / "etc/fstab"
    if fstab.is_file():
        original = fstab.read_text()
        filtered_lines = []
        for line in original.splitlines(keepends=True):
            fields = line.split("#", 1)[0].split()
            if len(fields) >= 3 and fields[2] == "swap":
                continue
            filtered_lines.append(line)
        filtered = "".join(filtered_lines)
        if filtered != original:
            settings["etc/fstab"] = filtered.encode()
    return settings


def configuration_state(path):
    if path.is_symlink():
        return os.readlink(path), None
    if path.exists():
        if not path.is_file():
            raise ValueError(f"Unexpected managed configuration path: {path}")
        return path.read_bytes(), path.stat()
    return None, None


def write_configuration(path, contents, metadata=None):
    if contents is None:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".pocketnet-", dir=path.parent) as temp:
        staged = Path(temp) / path.name
        if isinstance(contents, str):
            staged.symlink_to(contents)
        else:
            staged.write_bytes(contents)
            if metadata:
                os.chown(staged, metadata.st_uid, metadata.st_gid)
            staged.chmod(stat.S_IMODE(metadata.st_mode) if metadata else 0o644)
        os.replace(staged, path)


def configuration_units(paths):
    units = []
    for path in paths:
        if path.endswith("journald.conf.d/pocketnet.conf"):
            units.append("systemd-journald.service")
        if path.endswith(("piagent-kismet.service", "kismet/piagent.conf")):
            units.append("piagent-kismet.service")
        if path.endswith("piagent-kismet-provision.service"):
            units.append("piagent-kismet-provision.service")
        if path.endswith("piagent-wireless-manager.service"):
            units.append("piagent-wireless-manager.service")
        if path.endswith(("piagent-telemetry.service", "piagent-telemetry.service.d/90-pocketnet-image.conf")):
            units.append("piagent-telemetry.service")
        if path.endswith("piagent-ble-time-sync.service.d/90-pocketnet-image.conf"):
            units.append("piagent-ble-time-sync.service")
        if path.endswith("etc/default/zramswap"):
            units.append("zramswap.service")
        for unit in ("piagent-hotspot.service", "piagent-dhcp.service"):
            if path.endswith("/" + unit):
                units.append(unit)
    return units


def ensure_zram_tools(root, live):
    if not live:
        return
    installed = subprocess.run(["dpkg-query", "-W", "-f=${db:Status-Abbrev}", "zram-tools"],
                               text=True, capture_output=True, timeout=10)
    if installed.returncode != 0 or not installed.stdout.startswith("ii "):
        subprocess.run(["apt-get", "-o", "Dpkg::Use-Pty=0", "install", "-y", "--no-install-recommends", "zram-tools"],
                       check=True, timeout=300)
    active_swap = subprocess.run(["swapon", "--show=NAME", "--noheadings", "--raw"],
                                 text=True, capture_output=True, check=True, timeout=10)
    for name in active_swap.stdout.splitlines():
        name = name.strip()
        if name and not Path(name).name.startswith("zram"):
            subprocess.run(["swapoff", name], check=True, timeout=120)
    subprocess.run(["systemctl", "mask", "swapfile.swap", "dphys-swapfile.service"],
                   check=True, timeout=20)


def install(root, live, archive, expected_sha):
    prefix = root / "opt/pocketnet"
    prefix.mkdir(parents=True, exist_ok=True)
    releases = prefix / "releases"
    releases.mkdir(exist_ok=True)
    with (prefix / ".release.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        with tempfile.TemporaryDirectory(prefix=".release-", dir=prefix) as temporary:
            staging = Path(temporary)
            trusted_archive = staging / "package.tar.gz"
            shutil.copyfile(archive, trusted_archive)
            if sha256(trusted_archive) != expected_sha:
                raise ValueError("Release archive SHA256 mismatch")
            payload = staging / "payload"
            unpack(trusted_archive, payload)
            manifest = validate_payload(payload)
            validate_host(root, live, payload, manifest)
            ensure_zram_tools(root, live)
            release = releases / manifest["version"]
            if release.is_symlink():
                raise ValueError("Version directory may not be a symlink")
            if release.exists():
                saved = validate_payload(release)
                if any(saved[field] != manifest[field] for field in ("files", *REQUIRED_VERSION_FIELDS)):
                    raise ValueError("An existing release uses this version with different contents")
            else:
                os.replace(payload, release)

            previous = current_link(prefix)
            selected = f"releases/{release.name}"
            before = validate_payload(prefix / previous)["files"] if previous else {}
            config = managed_configuration(root, release)
            prior_config = {path: configuration_state(root / path) for path in config}
            changes = {path: value for path, value in config.items() if prior_config[path][0] != value}
            units = [unit for unit in dict.fromkeys(configuration_units(changes) +
                     changed_units(before, manifest["files"])) if live and active(unit)]
            lab_name = "piagent-active-lab.service"
            lab_path = "etc/systemd/system/piagent-active-lab.service"
            retiring_lab = live and config.get(lab_path) is None and active(lab_name)
            if retiring_lab:
                units = [name for name in units if name != lab_name]
            control_unit = "piagent-control.socket"
            control_installed = config.get("etc/systemd/system/piagent-control.socket") is not None
            control_was_running = live and active(control_unit)
            stopped_control = False
            started_control = False
            stopped_lab = False
            # Restarting the hotspot also affects its DHCP and telemetry
            # consumers. Include previously active consumers explicitly so an
            # SSH update cannot leave them stopped after the hotspot recovers.
            if "piagent-hotspot.service" in units:
                for unit in ("piagent-dhcp.service", "piagent-telemetry.service"):
                    if unit not in units and active(unit):
                        units.append(unit)
            applied = []
            try:
                if retiring_lab:
                    subprocess.run(["systemctl", "stop", lab_name], check=True, timeout=20)
                    stopped_lab = True
                if control_was_running and not control_installed:
                    subprocess.run(["systemctl", "stop", control_unit], check=True, timeout=20)
                    stopped_control = True
                for path, value in changes.items():
                    write_configuration(root / path, value, prior_config[path][1])
                    applied.append(path)
                if previous != selected:
                    set_current(prefix, selected)
                if control_installed:
                    args = ["systemd-sysusers"]
                    if not live:
                        args.append(f"--root={root}")
                    subprocess.run([*args, "piagent-control.conf"], check=True, timeout=20)
                if live and applied:
                    subprocess.run(["systemctl", "daemon-reload"], check=True, timeout=20)
                if live and control_installed and not control_was_running:
                    subprocess.run(["systemctl", "start", control_unit], check=True, timeout=20)
                    started_control = True
                restart(units)
                if live and config.get(lab_path) is not None and (root / "etc/piagent-kismet/monitor.json").is_file():
                    if not active(lab_name):
                        subprocess.run(["systemctl", "start", lab_name], check=True, timeout=20)
                if live:
                    subprocess.run(["systemctl", "enable", "zramswap.service"], check=True, timeout=20)
                    if not active("zramswap.service"):
                        subprocess.run(["systemctl", "start", "zramswap.service"], check=True, timeout=30)

                    # API keys live in Kismet's volatile session DB. Ensure the
                    # per-start provisioner is enabled, then refresh credentials
                    # before restarting consumers which read the /run files.
                    subprocess.run(["systemctl", "enable", "piagent-kismet-provision.service"],
                                   check=True, timeout=20)
                    if active("piagent-kismet.service") and not active("piagent-kismet-provision.service"):
                        subprocess.run(["systemctl", "start", "piagent-kismet-provision.service"],
                                       check=True, timeout=45)
                        consumers = [unit for unit in
                                     ("piagent-telemetry.service", "piagent-wireless-manager.service")
                                     if active(unit)]
                        restart(consumers)
                place_updater(prefix, release / "install.sh")
            except BaseException:
                if current_link(prefix) == selected:
                    if previous:
                        set_current(prefix, previous)
                    else:
                        (prefix / "current").unlink()
                try:
                    if started_control:
                        subprocess.run(["systemctl", "stop", control_unit], check=True, timeout=20)
                    for path in reversed(applied):
                        write_configuration(root / path, *prior_config[path])
                    if live and applied:
                        subprocess.run(["systemctl", "daemon-reload"], check=True, timeout=20)
                    if stopped_control:
                        subprocess.run(["systemctl", "start", control_unit], check=True, timeout=20)
                    if previous:
                        restart(units)
                        if stopped_lab and not active(lab_name):
                            subprocess.run(["systemctl", "start", lab_name], check=True, timeout=20)
                except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                    print(f"Rollback configuration or service restart failed: {error}", file=sys.stderr)
                raise
            print(f"Installed PocketNet release {release.name}")


def interrupted(signum, _):
    raise KeyboardInterrupt(f"signal {signum}")


def main():
    parser = argparse.ArgumentParser(description="Install a PocketNet Ubuntu 22.04 ARM64 release")
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--root", type=Path, help="mounted image root for offline installation")
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    if not SHA256.fullmatch(args.sha256):
        parser.error("--sha256 must be a 64-digit SHA256 digest")
    root = args.root.resolve(strict=True) if args.root else Path("/")
    if args.root and root == Path("/"):
        parser.error("--root must point to an offline image root")
    os.umask(0o022)
    signal.signal(signal.SIGTERM, interrupted)
    try:
        install(root, args.root is None, args.archive, args.sha256.lower())
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError, tarfile.TarError, KeyboardInterrupt) as error:
        print(f"PocketNet release installation failed: {error}", file=sys.stderr)
        return 1
    return 0


raise SystemExit(main())
PYTHON
