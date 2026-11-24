#!/usr/bin/env bash
set -euo pipefail
umask 077

app=/opt/pocketnet/current
python=/opt/pocketnet/python/bin/python3.12
state=/var/lib/pocketnet
tls=/etc/piagent-https
registry=/var/lib/piagent-devices
qr=/root/piagent-enrollment.svg

install -d -m 0700 "$state"
exec 9>/run/lock/pocketnet-firstboot.lock
flock -n 9
[[ ! -e "$state/firstboot-complete" ]] || exit 0
cd "$app"
export PYTHONDONTWRITEBYTECODE=1

# Make management access available before identity, Bluetooth or Kismet setup.
# The hotspot unit creates an empty PSK file only on a new device and preserves
# all registered-phone keys on subsequent starts.
systemctl start piagent-hotspot.service piagent-dhcp.service
for ((attempt = 0; attempt < 12; attempt++)); do
    if [[ "$(hostapd_cli -i wlan0 ping 2>/dev/null)" == PONG ]]; then
        break
    fi
    sleep 1
done
[[ "$(hostapd_cli -i wlan0 ping 2>/dev/null)" == PONG ]]

read -r build_epoch < /etc/pocketnet/build-epoch
[[ "$build_epoch" =~ ^[0-9]{10}$ ]]
if [[ "$(date +%s)" -lt "$build_epoch" ]]; then
    echo 'System time predates the image build. BLE can synchronize it after enrollment.'
fi

# Commit CA and leaf together so a partial pair can never reach enrollment.
if [[ ! -e "$tls" ]]; then
    pending=/etc/.pocketnet-tls.pending
    install -d -m 0700 "$pending"
    "$python" - "$pending" "$build_epoch" <<'PY'
from datetime import datetime, timedelta, timezone
from ipaddress import ip_address
from pathlib import Path
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

pending = Path(sys.argv[1])
now = max(datetime.now(timezone.utc), datetime.fromtimestamp(int(sys.argv[2]), timezone.utc))
ca_key = ec.generate_private_key(ec.SECP256R1())
server_key = ec.generate_private_key(ec.SECP256R1())
ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "PocketNet Local CA")])
server_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "192.168.4.1")])


def certificate(subject, public_key, days):
    return (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(ca_name)
        .public_key(public_key)
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(days=1))
        .not_valid_after(now + timedelta(days=days))
    )


ca = (
    certificate(ca_name, ca_key.public_key(), 3650)
    .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
    .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, False, False), critical=True)
    .sign(ca_key, hashes.SHA256())
)
server = (
    certificate(server_name, server_key.public_key(), 3650)
    .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
    .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
    .add_extension(x509.SubjectAlternativeName([x509.IPAddress(ip_address("192.168.4.1"))]), critical=False)
    .sign(ca_key, hashes.SHA256())
)
for name, key in (("ca.key", ca_key), ("server.key", server_key)):
    (pending / name).write_bytes(
        key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    )
for name, cert in (("ca.pem", ca), ("server.pem", server)):
    (pending / name).write_bytes(cert.public_bytes(serialization.Encoding.PEM))
PY
    chmod 0644 "$pending/ca.pem" "$pending/server.pem"
    sync -f "$pending"
    mv -T -- "$pending" "$tls"
    sync -f /etc
fi
[[ -s "$tls/ca.pem" && -s "$tls/server.pem" && -s "$tls/server.key" ]]

# Stage the registry and QR together. After a power loss, a staged QR can
# still be moved into place without ever rotating an installed device identity.
pending="$state/identity.pending"
if [[ ! -e "$registry" && ! -e "$qr" ]]; then
    install -d -m 0700 "$pending"
    if [[ ! -e "$pending/ready" ]]; then
        rm -f -- "$pending/registry/device.key" "$pending/registry/authority.json" \
            "$pending/registry/devices.sqlite3" "$pending/registry/devices.sqlite3-wal" \
            "$pending/registry/devices.sqlite3-shm" "$pending/registry/devices.sqlite3-journal" "$pending/qr.svg"
        "$python" -m raspberry.enrollment.admin --state "$pending/registry" init \
            --device-id "pocketnet-$(cut -c1-16 /etc/machine-id)" --ssid PiAgent \
            --telemetry-url https://192.168.4.1:9443 --ca-file "$tls/ca.pem" --qr-file "$pending/qr.svg"
        chown piagent-ble:piagent-enrollment "$pending/registry" \
            "$pending/registry/device.key" "$pending/registry/authority.json" "$pending/registry/devices.sqlite3"
        chmod 2750 "$pending/registry"
        sync -f "$pending"
        touch "$pending/ready"
        sync -f "$pending"
    fi
    mv -T -- "$pending/registry" "$registry"
    sync -f /var/lib
fi
if [[ ! -e "$qr" && -e "$pending/ready" ]]; then
    install -m 0600 "$pending/qr.svg" "$qr.pending"
    sync -f "$qr.pending"
    mv -T -- "$qr.pending" "$qr"
    sync -f /root
fi
[[ -s "$registry/device.key" && -s "$registry/authority.json" && -s "$registry/devices.sqlite3" && -s "$qr" ]]
if [[ -e "$pending/ready" ]]; then
    rm -f -- "$pending/qr.svg" "$pending/ready"
    rmdir -- "$pending"
fi
systemctl start bluetooth.service
rfkill unblock bluetooth
for ((attempt = 0; attempt < 12; attempt++)); do
    if timeout 3s bluetoothctl power on; then
        break
    fi
    sleep 1
done
timeout 3s bluetoothctl show | grep -q 'Powered: yes'
systemctl start piagent-clock.socket piagent-enrollment-wifi.socket piagent-ble-time-sync.service

"$python" raspberry/config/kismet/configure.py --runtime-only
if [[ -f /etc/pocketnet/usb-monitor.conf && ! -e /etc/piagent-kismet/monitor.json ]]; then
    if read -r interface vendor product port driver extra < /etc/pocketnet/usb-monitor.conf &&
        [[ -n "$driver" && -z "$extra" ]] &&
        "$python" raspberry/config/kismet/configure_monitor.py --runtime-only \
            --interface "$interface" --vendor "$vendor" --product "$product" --port "$port" --driver "$driver"; then
        udevadm control --reload
        udevadm trigger --action=add "/sys/class/net/$interface"
        systemctl restart piagent-kismet.service
    else
        echo 'USB monitor preset could not be applied. Continuing PocketNet initialization.' >&2
    fi
fi
if [[ -f /etc/piagent-kismet/monitor.json ]]; then
    systemctl enable --now piagent-wireless-manager.service
    # Lab daemon is idle by default. The installed profile remains disabled until an operator
    # provisions an owned, RF-isolated target explicitly.
    systemctl start piagent-active-lab.service || \
        echo 'Radio lab unavailable; passive monitoring remains usable.' >&2
else
    echo 'No USB monitor is assigned. Kismet will start in degraded mode.'
fi

systemctl start piagent-telemetry.service
for ((attempt = 0; attempt < 12; attempt++)); do
    if ss -H -lnt 'sport = :9443' | grep -Fq '192.168.4.1'; then
        break
    fi
    sleep 1
done
ss -H -lnt 'sport = :9443' | grep -Fq '192.168.4.1'
services=(piagent-hotspot.service piagent-dhcp.service piagent-clock.socket
    piagent-enrollment-wifi.socket piagent-ble-time-sync.service piagent-kismet.service piagent-telemetry.service)
for unit in "${services[@]}"; do
    systemctl is-active --quiet "$unit"
done
systemctl enable bluetooth.service "${services[@]}"
# On later boots Kismet's RAM session database is empty; regenerate its API keys
# before Telemetry and the wireless manager load their runtime credentials.
systemctl enable piagent-kismet-provision.service
touch "$state/firstboot-complete"
sync -f "$state"
