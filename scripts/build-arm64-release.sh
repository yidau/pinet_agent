#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

usage() {
    echo "Usage: $0 ROOTFS OUTPUT.tar.gz GIT_COMMIT" >&2
    exit 2
}

[[ $# -eq 3 && $EUID -eq 0 && $3 =~ ^[0-9a-f]{40}$ ]] || usage
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
root=$(realpath -e -- "$1")
output=$(realpath -m -- "$2")
commit=$3
jobs=${POCKETNET_BUILD_JOBS:-2}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || usage
[[ "$root" != / && -f "$root/etc/os-release" && -d "$root/tmp" && "$output" == *.tar.gz ]] || usage
if [[ "$output" == "$root/"* ]]; then
    echo "The release output must be outside the target root filesystem" >&2
    exit 1
fi
mountpoint -q "$root" || { echo "Target rootfs must be an isolated mount point" >&2; exit 1; }

target=$(chroot "$root" /bin/sh -ec '. /etc/os-release; printf "%s/%s/%s" "$ID" "$VERSION_ID" "$(dpkg --print-architecture)"')
if [[ "$target" != ubuntu/22.04/arm64 ]]; then
    echo "Expected ubuntu/22.04/arm64 build root, found $target" >&2
    exit 1
fi

mkdir -p -- "$(dirname -- "$output")"
work=$(mktemp -d -- "$root/tmp/pocketnet-arm64-build.XXXXXXXX")
archive=
cleanup() {
    local result=$?
    trap - EXIT
    if [[ -n "$archive" ]]; then rm -f -- "$archive"; fi
    rm -rf --one-file-system -- "$work"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
archive=$(mktemp -- "${output}.tmp.XXXXXXXX")

chroot_work=${work#"$root"}
cp -a -- "$source_dir/raspberry/telemetry" "$work/source"
chroot "$root" cmake -S "$chroot_work/source" -B "$chroot_work/build" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
chroot "$root" cmake --build "$chroot_work/build" --parallel "$jobs"
chroot "$root" cmake --install "$chroot_work/build" --prefix "$chroot_work/payload"

binary="$work/payload/bin/piagent-telemetry"
file -- "$binary"
readelf -h -- "$binary"
readelf -d -- "$binary"
if ! readelf -h -- "$binary" | grep -q 'Machine:[[:space:]]*AArch64'; then
    echo "The telemetry binary is not AArch64" >&2
    exit 1
fi
libraries=$(chroot "$root" /usr/bin/ldd "$chroot_work/payload/bin/piagent-telemetry")
printf '%s\n' "$libraries"
if [[ "$libraries" == *'not found'* ]]; then
    echo "The telemetry binary has unresolved target libraries" >&2
    exit 1
fi

install -d -- "$work/payload/raspberry"
for component in config control enrollment time_sync wireless; do
    cp -a -- "$source_dir/raspberry/$component" "$work/payload/raspberry/"
done
find "$work/payload" -type d -name __pycache__ -prune -exec rm -rf -- {} +
install -m 0755 -- "$source_dir/deploy/release/install.sh" "$work/payload/install.sh"
install -m 0644 -- "$source_dir/raspberry/telemetry/piagent-telemetry.service" "$work/payload/raspberry/config/runtime/"
install -m 0644 -- "$source_dir/deploy/systemd/piagent-ble-time-sync.conf" "$work/payload/raspberry/config/runtime/"
install -m 0644 -- "$source_dir/deploy/systemd/piagent-telemetry.conf" "$work/payload/raspberry/config/runtime/"
for unit in piagent-hotspot.service piagent-dhcp.service; do
    install -m 0644 -- "$source_dir/deploy/systemd/$unit" "$work/payload/raspberry/config/runtime/"
done
for file in piagent-control.socket piagent-control@.service piagent-control.sysusers.conf; do
    install -m 0644 -- "$source_dir/deploy/systemd/$file" "$work/payload/raspberry/config/runtime/"
done
install -m 0644 -- "$source_dir/raspberry/config/runtime/zramswap" "$work/payload/raspberry/config/runtime/"

python_version=$(chroot "$root" /opt/pocketnet/python/bin/python3.12 --version)
[[ "$python_version" == 'Python 3.12.'* ]] || { echo "The image needs ARM64 Python 3.12" >&2; exit 1; }
kismet=$(chroot "$root" dpkg-query -W -f='${Version}' kismet-core)
capture=$(chroot "$root" dpkg-query -W -f='${Version}' kismet-capture-linux-wifi)
if [[ "$kismet" != "$capture" ]]; then
    echo "Kismet core and Linux Wi-Fi capture must use the same package version" >&2
    exit 1
fi
protobuf=$(chroot "$root" pkg-config --modversion protobuf)
grpc=$(chroot "$root" pkg-config --modversion grpc++)
gxx=$(chroot "$root" g++ -dumpfullversion)
python3 - "$work/payload" "$source_dir/deploy/release/manifest-template.json" \
    "$commit" "${python_version#Python }" "$kismet" "$protobuf" "$grpc" "$gxx" <<'PYTHON'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

payload, template, commit, python, kismet, protobuf, grpc, compiler = sys.argv[1:]
root = Path(payload)
manifest = json.loads(Path(template).read_text())
manifest.update(
    git_commit=commit,
    version=commit,
    python_version=python,
    kismet_version=kismet,
    protobuf_version=protobuf,
    grpc_version=grpc,
    cpp_compiler_version=compiler,
    built_at=datetime.now(timezone.utc).isoformat(timespec="seconds"),
)
manifest["files"] = {
    path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted(root.rglob("*"))
    if path.is_file()
}
(root / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
PYTHON
tar --sort=name --owner=0 --group=0 --numeric-owner -C "$work/payload" \
    -czf "$archive" bin raspberry install.sh manifest.json
chmod 0644 -- "$archive"
mv -fT -- "$archive" "$output"
archive=
printf 'ARM64 release: %s\n' "$output"
sha256sum -- "$output"
