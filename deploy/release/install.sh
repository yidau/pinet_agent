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
import struct
import subprocess
import sys
import tarfile
import tempfile
import time


RELEASE = re.compile(r"[a-f0-9]{40}")
SHA256 = re.compile(r"[a-fA-F0-9]{64}")
TELEMETRY = "bin/piagent-telemetry"
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
    if any(file.startswith("raspberry/wireless/") for file in changes):
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
            if previous == selected:
                place_updater(prefix, release / "install.sh")
                print(f"PocketNet {release.name} is already installed")
                return
            before = validate_payload(prefix / previous)["files"] if previous else {}
            units = [unit for unit in changed_units(before, manifest["files"]) if live and active(unit)]
            try:
                set_current(prefix, selected)
                restart(units)
                place_updater(prefix, release / "install.sh")
            except BaseException:
                if current_link(prefix) == selected:
                    if previous:
                        set_current(prefix, previous)
                        try:
                            restart(units)
                        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
                            print(f"Rollback service restart failed: {error}", file=sys.stderr)
                    else:
                        (prefix / "current").unlink()
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
