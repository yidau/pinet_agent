#!/usr/bin/env bash
set -Eeuo pipefail
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 22.04 ]] || { echo 'Ubuntu 22.04 WSL2 is required.' >&2; exit 1; }
[[ "$(uname -m)" == x86_64 && "$(uname -r)" == *WSL2* ]] || { echo 'An x86_64 WSL2 kernel is required.' >&2; exit 1; }
(( $(df --output=avail /var/cache | tail -1) >= 20 * 1024 * 1024 )) || { echo 'At least 20 GiB is required in the WSL filesystem.' >&2; exit 1; }
if (( EUID != 0 )); then exec sudo -- bash "$0" "$@"; fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  git curl wget ca-certificates gnupg gpgv ubuntu-keyring openssh-client xz-utils zstd \
  build-essential cmake ninja-build pkg-config python3 python3-venv python3-pip \
  protobuf-compiler protobuf-compiler-grpc libprotobuf-dev libgrpc++-dev libssl-dev \
  libsqlite3-dev libcurl4-openssl-dev nlohmann-json3-dev qemu-user-static binfmt-support \
  e2fsprogs dosfstools parted fdisk util-linux rsync file jq
if [[ ! -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    update-binfmts --enable qemu-aarch64
fi
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64 ||
    { echo 'ARM64 binfmt handler is unavailable in this WSL instance.' >&2; exit 1; }

tmp=$(mktemp -d)
loop=
cleanup() {
    if mountpoint -q "$tmp/root"; then umount "$tmp/root"; fi
    if [[ -n "$loop" ]]; then losetup -d "$loop"; fi
    rm -f -- "$tmp/loop.img"
    rmdir "$tmp/root" "$tmp"
}
trap cleanup EXIT
mkdir "$tmp/root"
truncate -s 32M "$tmp/loop.img"
mke2fs -q -F -t ext4 "$tmp/loop.img"
loop=$(losetup --find --show --nooverlap "$tmp/loop.img")
mount "$loop" "$tmp/root"
echo "WSL2 $(uname -r), $PRETTY_NAME, $(uname -m)"
df -h /var/cache
losetup "$loop"
if command -v docker >/dev/null && timeout 5 docker info >/dev/null 2>&1; then
    echo 'Docker is available.'
else
    echo 'Docker is optional and is unavailable.'
fi
echo 'ARM64 binfmt and loop mount checks passed.'
