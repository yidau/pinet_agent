#!/usr/bin/env bash
set -Eeuo pipefail
if (( $# != 1 )); then echo 'Usage: verify-image.sh IMAGE.img[.xz]' >&2; exit 2; fi
image=$(realpath -e -- "$1")
if (( EUID != 0 )); then exec sudo -- bash "$0" "$image"; fi
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$repo/deploy/image/image.env"
. "$repo/deploy/image/loop-image.sh"
work=$(mktemp -d)
root="$work/root"
loop=
cleanup() {
    local status=$?
    trap - EXIT
    if ! close_image; then echo "Could not release $root or $loop" >&2; exit 1; fi
    if [[ -f "$work/pocketnet.img" ]]; then rm -f -- "$work/pocketnet.img"; fi
    rmdir -- "$root" "$work"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'echo "Image verification failed at line $LINENO" >&2' ERR
mkdir "$root"
if [[ "$image" == *.xz ]]; then
    xz -dc -- "$image" > "$work/pocketnet.img"
    image="$work/pocketnet.img"
fi
open_image --read-only
mount -t ext4 -o ro,noload "${loop}p2" "$root"
boot="$root/boot/firmware"
mount -t vfat -o ro "${loop}p1" "$boot"
test -s "$boot/config.txt"
test -s "$boot/cmdline.txt"
test -f "$boot/meta-data"
[[ "$(chroot "$root" dpkg --print-architecture)" == arm64 ]]
chroot "$root" sh -c '. /etc/os-release; test "$VERSION_ID" = 22.04'
app=/opt/pocketnet/current
bin="$app/bin/piagent-telemetry"
file "$root$bin"
elf_header=$(readelf -h "$root$bin")
grep -Eq 'Machine:.*AArch64' <<< "$elf_header"
dynamic=$(readelf -d "$root$bin")
grep -E 'NEEDED.*libgrpc' <<< "$dynamic"
dependencies=$(chroot "$root" ldd "$bin")
if grep -q 'not found' <<< "$dependencies"; then
    printf '%s\n' "$dependencies" >&2
    exit 1
fi
chroot "$root" /opt/pocketnet/python/bin/python -c 'import sys, cryptography, dbus_next, qrcode; assert sys.version_info[:2] == (3, 12); print(sys.version)'
for package in kismet-core kismet-capture-linux-wifi; do
    chroot "$root" dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' "$package" | grep -E '^ii '
done
capture=/usr/bin/kismet_cap_linux_wifi
if [[ ! -u "$root$capture" ]]; then
    cap=$(chroot "$root" getcap "$capture")
    [[ "$cap" == *cap_net_admin* && "$cap" == *cap_net_raw* ]]
fi
grep -RqE 'filter_mgmt=true' "$root$app" 2>/dev/null
for unit in pocketnet-firstboot piagent-telemetry piagent-kismet piagent-wireless-manager piagent-ble-time-sync; do
    [[ -f "$root/etc/systemd/system/$unit.service" ]]
done
if [[ "$ENABLE_FIRST_BOOT" == true ]]; then
    systemctl --root="$root" is-enabled pocketnet-firstboot.service
fi
[[ ! -e "$root/etc/systemd/system/piagent-mcp.service" && ! -e "$root$app/raspberry/mcp_server" ]]
[[ ! -e "$root/var/lib/piagent-devices/devices.sqlite3" ]]
if [[ "$ENABLE_SSH" == true ]]; then
    systemctl --root="$root" is-enabled ssh.service
    cmp -- "$boot/network-config" "$repo/deploy/image/network-config"
    grep -qx '  - name: yidau' "$boot/user-data"
    grep -qx 'ssh_pwauth: false' "$boot/user-data"
    grep -q 'ssh_authorized_keys:' "$boot/user-data"
    if compgen -G "$root/etc/ssh/ssh_host_*_key" >/dev/null; then
        echo 'Unexpected pre-generated SSH host keys.' >&2
        exit 1
    fi
fi
if find "$root/root" "$root/home" -type f \( -name id_rsa -o -name id_ed25519 -o -name id_ecdsa \) -print -quit | grep -q .; then
    echo 'Unexpected SSH private key in a home directory.' >&2
    exit 1
fi
echo 'PocketNet image checks passed.'
