#!/usr/bin/env bash
# Install units and configuration into a mounted image without starting services.
set -euo pipefail

if (( $# != 1 || EUID != 0 )); then
    echo "Usage: sudo bash $0 MOUNTED_ROOT" >&2
    exit 2
fi
root=$(realpath -e -- "$1")
[[ "$root" != / && -f "$root/etc/os-release" && -d "$root/etc/systemd/system" ]]
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
unit_dir="$root/etc/systemd/system"
release="$root/opt/pocketnet/current"
if [[ ! -x "$release/bin/piagent-telemetry" ]]; then
    echo 'The ARM64 telemetry release must be installed first.' >&2
    exit 1
fi
for executable in /opt/pocketnet/python/bin/python3.12 /usr/bin/kismet /usr/bin/kismet_cap_linux_wifi \
    /usr/sbin/hostapd /usr/sbin/dnsmasq; do
    if ! chroot "$root" /usr/bin/test -x "$executable"; then
        echo "Missing executable in the image: $executable" >&2
        exit 1
    fi
done

install -d -m 0755 "$root/etc/pocketnet" "$root/etc/sysusers.d" "$root/etc/hostapd"
install -D -m 0755 "$source_dir/deploy/image/firstboot.sh" "$root/usr/local/lib/pocketnet/firstboot.sh"
install -m 0644 "$source_dir/deploy/image/firstboot.service" "$unit_dir/pocketnet-firstboot.service"
install -m 0644 "$source_dir/deploy/systemd/piagent-hotspot.service" \
    "$source_dir/deploy/systemd/piagent-dhcp.service" "$unit_dir/"

for service in raspberry/config/time-sync/{piagent-ble-time-sync.service,piagent-clock.service,piagent-clock.socket} \
    raspberry/config/enrollment/{piagent-enrollment-wifi.service,piagent-enrollment-wifi.socket} \
    raspberry/config/kismet/piagent-wireless-manager.service raspberry/config/kismet/piagent-kismet-provision.service; do
    install -m 0644 "$source_dir/$service" "$unit_dir/"
done
install -m 0644 "$source_dir/raspberry/config/time-sync/piagent-time-sync.sysusers.conf" \
    "$source_dir/raspberry/config/enrollment/piagent-enrollment.sysusers.conf" "$root/etc/sysusers.d/"
install -m 0644 "$source_dir/deploy/systemd/pocketnet-kismet.sysusers.conf" "$root/etc/sysusers.d/"
for service in piagent-clock piagent-enrollment-wifi piagent-telemetry piagent-wireless-manager; do
    install -D -m 0644 "$source_dir/deploy/systemd/$service.conf" "$unit_dir/$service.service.d/90-pocketnet-image.conf"
done
install -m 0644 "$source_dir/deploy/systemd/hostapd.conf" "$root/etc/hostapd/piagent.conf"
install -m 0644 "$source_dir/deploy/systemd/dnsmasq.conf" "$root/etc/piagent-dnsmasq.conf"
install -D -m 0644 "$source_dir/raspberry/config/runtime/zramswap" "$root/etc/default/zramswap"

# Remove block-backed swap entries from the image; PocketNet enables zram below.
if [[ -f "$root/etc/fstab" ]]; then
    awk '$1 !~ /^#/ && NF >= 3 && $3 == "swap" { next } { print }' \
        "$root/etc/fstab" > "$root/etc/fstab.pocketnet"
    chmod --reference="$root/etc/fstab" "$root/etc/fstab.pocketnet"
    chown --reference="$root/etc/fstab" "$root/etc/fstab.pocketnet"
    mv -f "$root/etc/fstab.pocketnet" "$root/etc/fstab"
fi
if grep -qx '\[Policy\]' "$root/etc/bluetooth/main.conf"; then
    sed -i '/^AutoEnable=/d; /^\[Policy\]$/a AutoEnable=true' "$root/etc/bluetooth/main.conf"
else
    printf '\n[Policy]\nAutoEnable=true\n' >> "$root/etc/bluetooth/main.conf"
fi
printf '%s\n' "$(date -u +%s)" > "$root/etc/pocketnet/build-epoch"
chmod 0644 "$root/etc/pocketnet/build-epoch"

systemd-sysusers --root="$root"
systemctl --root="$root" mask hostapd.service swapfile.swap dphys-swapfile.service
systemctl --root="$root" enable zramswap.service
if [[ -e "$root/lib/systemd/system/kismet.service" || -e "$root/usr/lib/systemd/system/kismet.service" ]]; then
    systemctl --root="$root" mask kismet.service
fi
systemctl --root="$root" enable pocketnet-firstboot.service
