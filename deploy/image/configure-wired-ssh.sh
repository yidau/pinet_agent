#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 || $# != 3 )); then
    echo 'Usage as root: configure-wired-ssh.sh ROOTFS BOOTFS SSH_PUBLIC_KEY_FILE' >&2
    exit 2
fi

rootfs=$(realpath -e -- "$1")
bootfs=$(realpath -e -- "$2")
key_file=$(realpath -e -- "$3")
script_dir=$(dirname -- "$(realpath -e -- "$0")")

if [[ "$rootfs" == / || "$bootfs" == / || "$rootfs" == "$bootfs" ||
    ! -x "$rootfs/usr/sbin/sshd" || ! -f "$bootfs/config.txt" ||
    ! -f "$bootfs/cmdline.txt" || ! -f "$bootfs/meta-data" || ! -f "$key_file" ]]; then
    echo 'Expected the Ubuntu Raspberry Pi root and system-boot trees and an OpenSSH public key file.' >&2
    exit 2
fi

mapfile -t key_lines < "$key_file"
if (( ${#key_lines[@]} != 1 )); then
    echo 'SSH public key file must contain one OpenSSH public key.' >&2
    exit 2
fi

# Discard the comment and accept CRLF from Windows. Only validated tokens reach YAML.
read -r key_type key_blob key_comment <<< "${key_lines[0]%$'\r'}"
case "$key_type" in
    ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521|\
    sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com) ;;
    *) echo 'Unsupported OpenSSH public key type.' >&2; exit 2 ;;
esac
if [[ ! "$key_blob" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]; then
    echo 'Invalid OpenSSH public key encoding.' >&2
    exit 2
fi
if ! ssh-keygen -l -f /dev/stdin >/dev/null <<< "$key_type $key_blob"; then
    echo 'Invalid OpenSSH public key.' >&2
    exit 2
fi

# Write the vendor NoCloud seed. Keep its metadata and the Pi boot files intact.
cat -- "$script_dir/network-config" > "$bootfs/network-config"
cat > "$bootfs/user-data" <<EOF
#cloud-config
users:
  - name: yidau
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: true
    ssh_authorized_keys:
      - '$key_type $key_blob'
ssh_pwauth: false
disable_root: true
ssh_deletekeys: true
ssh_genkeytypes: [ed25519, ecdsa, rsa]
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
EOF

install -d -m 0755 -- "$rootfs/etc/ssh/sshd_config.d" "$rootfs/etc/systemd/system/ssh.service.d"
cat > "$rootfs/etc/ssh/sshd_config.d/00-pocketnet-debug.conf" <<'EOF'
AuthenticationMethods publickey
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
cat > "$rootfs/etc/systemd/system/ssh.service.d/10-pocketnet-cloud-init.conf" <<'EOF'
[Unit]
Wants=cloud-init.service
After=cloud-init.service
EOF

# Package installation may generate host keys inside the chroot. Each Pi gets
# its own keys when cloud-init processes the seed on first boot.
rm -f -- "$rootfs"/etc/ssh/ssh_host_*_key "$rootfs"/etc/ssh/ssh_host_*_key.pub
systemctl --root="$rootfs" enable ssh.service
