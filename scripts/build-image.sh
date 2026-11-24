#!/usr/bin/env bash
set -Eeuo pipefail
repo=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
config="$repo/deploy/image"
. "$config/image.env"
include_mdk4=${POCKETNET_INCLUDE_MDK4:-false}
case "$include_mdk4" in
    true|false) ;;
    *) echo 'POCKETNET_INCLUDE_MDK4 must be true or false.' >&2; exit 2 ;;
esac

public_key=${1:-${POCKETNET_SSH_PUBLIC_KEY:-}}
if [[ "$ENABLE_SSH" == true && -z "$public_key" ]]; then
    public_key="$HOME/.ssh/id_ed25519.pub"
    if [[ ! -r "$public_key" ]] && command -v powershell.exe >/dev/null; then
        profile=$(powershell.exe -NoProfile -NonInteractive -Command '[Environment]::GetFolderPath("UserProfile")' | tr -d '\r')
        public_key="$(wslpath -u "$profile")/.ssh/id_ed25519.pub"
    fi
fi
if [[ "$ENABLE_SSH" == true ]]; then
    [[ -n "$public_key" && -r "$public_key" ]] ||
        { echo 'Provide an OpenSSH public key as the first argument, or set POCKETNET_SSH_PUBLIC_KEY.' >&2; exit 1; }
    public_key=$(realpath -- "$public_key")
    ssh-keygen -lf "$public_key" >/dev/null
fi
commit=${POCKETNET_COMMIT:-}
if [[ -z "$commit" && "$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" == "$repo" ]]; then
    commit=$(git -C "$repo" rev-parse HEAD)
fi
[[ "$commit" =~ ^[[:xdigit:]]{40}$ ]] ||
    { echo 'Use a Git checkout, or set POCKETNET_COMMIT for a pinned source archive.' >&2; exit 1; }

if (( EUID != 0 )); then
    exec sudo -- env "POCKETNET_COMMIT=$commit" "POCKETNET_INCLUDE_MDK4=$include_mdk4" bash "$0" "$public_key"
fi
. /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 22.04 && "$(uname -m)" == x86_64 && "$(uname -r)" == *WSL2* ]] ||
    { echo 'Build on Ubuntu 22.04 x86_64 WSL2.' >&2; exit 1; }
[[ "$UBUNTU_ARCH" == arm64 && "$TARGET_BOARD" == rpi4 && "$KISMET_CHANNEL" == jammy && "$BUILD_TYPE" == Release ]] ||
    { echo 'This builder supports Raspberry Pi 4, Jammy ARM64 and Release only.' >&2; exit 1; }
for tool in curl gpgv jq losetup parted sfdisk qemu-aarch64-static resize2fs; do
    command -v "$tool" >/dev/null || { echo "Install $tool with scripts/bootstrap-wsl.sh." >&2; exit 1; }
done
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64
grep -Eq '^flags:.*F' /proc/sys/fs/binfmt_misc/qemu-aarch64

cache=/var/cache/pocketnet-image
install -d -m 0755 "$cache" "$cache/base" "$cache/logs" "$cache/apt-arm64"
exec 9>"$cache/build.lock"
flock -n 9 || { echo 'Another PocketNet build owns the cache.' >&2; exit 1; }
log=$(mktemp "$cache/logs/image.XXXXXXXX.log")
echo "Build log: $log"
exec > >(tee -a "$log") 2>&1
work=$(mktemp -d "$cache/build.XXXXXXXX")
root="$work/root"
image="$work/pocketnet.img"
loop=
stage=
previous=
. "$config/loop-image.sh"

cleanup() {
    local status=$?
    trap - EXIT
    if ! close_image; then
        echo "Cleanup could not release $work; inspect it before retrying." >&2
        exit 1
    fi
    if [[ -n "$previous" && ! -e "$repo/dist" ]]; then mv -T -- "$previous" "$repo/dist"; fi
    if [[ -n "$stage" && -d "$stage" ]]; then rm -r -- "$stage"; fi
    rm -r -- "$work"
    if ((status != 0)); then echo "Build failed. See $log" >&2; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'echo "Build failed at line $LINENO" >&2' ERR
install -d "$root"

base="ubuntu-${UBUNTU_RELEASE}-preinstalled-server-arm64+raspi.img.xz"
url=https://cdimage.ubuntu.com/ubuntu/releases/jammy/release
download() {
    curl --fail --location --silent --show-error --retry 2 --connect-timeout 15 "$1" -o "$2.part"
    mv -- "$2.part" "$2"
}
cd "$cache/base"
if ! gpgv --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg SHA256SUMS.gpg SHA256SUMS 2>/dev/null; then
    download "$url/SHA256SUMS" SHA256SUMS
    download "$url/SHA256SUMS.gpg" SHA256SUMS.gpg
    gpgv --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg SHA256SUMS.gpg SHA256SUMS
fi
entry=$(awk -v target="*$base" '$2 == target {print}' SHA256SUMS)
[[ "$entry" =~ ^[a-f0-9]{64}[[:blank:]] ]] || { echo "$base missing from signed checksums." >&2; exit 1; }
if ! sha256sum -c <<< "$entry"; then download "$url/$base" "$base"; fi
sha256sum -c <<< "$entry"
base_sha=${entry%% *}
xz -dc -- "$base" > "$image"
sfdisk --json "$image" > "$work/partitions.json"
jq -e '.partitiontable.partitions|length == 2' "$work/partitions.json" >/dev/null
(( $(stat -c %s "$image") < IMAGE_SIZE_GIB * 1024 ** 3 )) || { echo 'IMAGE_SIZE_GIB is too small.' >&2; exit 1; }
truncate -s "${IMAGE_SIZE_GIB}G" "$image"
sfdisk --no-reread --no-tell-kernel -N 2 "$image" <<< ', +'
sfdisk --verify "$image"
open_image
if e2fsck -fy "${loop}p2"; then :; else [[ $? -eq 1 ]]; fi
resize2fs "${loop}p2"
mount "${loop}p2" "$root"
mount "${loop}p1" "$root/boot/firmware"
mount --bind "$cache/apt-arm64" "$root/var/cache/apt/archives"
mount -t proc proc "$root/proc"
mount -t tmpfs -o mode=0755 tmpfs "$root/dev"
mknod -m 0666 "$root/dev/null" c 1 3
mknod -m 0666 "$root/dev/zero" c 1 5
mknod -m 0666 "$root/dev/random" c 1 8
mknod -m 0666 "$root/dev/urandom" c 1 9
mknod -m 0666 "$root/dev/tty" c 5 0

# Keep target daemons and the target DNS symlink out of the build environment.
for target in etc/resolv.conf usr/sbin/policy-rc.d; do
    if [[ -e "$root/$target" || -L "$root/$target" ]]; then
        mv -- "$root/$target" "$work/${target##*/}.original"
    fi
done
install -m 0644 /etc/resolv.conf "$root/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 0755 "$root/usr/sbin/policy-rc.d"
arm() { chroot "$root" /usr/bin/env DEBIAN_FRONTEND=noninteractive SYSTEMD_OFFLINE=1 "$@"; }
[[ "$(arm dpkg --print-architecture)" == arm64 ]]
arm sh -c '. /etc/os-release; test "$VERSION_ID" = 22.04'
echo 'ARM64 Jammy chroot ready.'

key_dir="$root/usr/share/keyrings"
install -d -m 0755 "$key_dir"
python_ppa_fingerprint=F23C5A6CF475977595C89F51BA6932366A755776
download "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$python_ppa_fingerprint" "$work/deadsnakes.asc"
fingerprint=$(gpg --batch --show-keys --with-colons "$work/deadsnakes.asc" |
    awk -F: '$1 == "fpr" && !seen++ {print $10}')
[[ "$fingerprint" == "$python_ppa_fingerprint" ]]
download https://www.kismetwireless.net/repos/kismet-release.gpg.key "$work/kismet.asc"
gpg --batch --yes --dearmor -o "$key_dir/pocketnet-python.gpg" "$work/deadsnakes.asc"
gpg --batch --yes --dearmor -o "$key_dir/pocketnet-kismet.gpg" "$work/kismet.asc"
printf '%s\n' 'deb [signed-by=/usr/share/keyrings/pocketnet-python.gpg] http://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu jammy main' \
    > "$root/etc/apt/sources.list.d/pocketnet-python.list"
printf 'deb [signed-by=/usr/share/keyrings/pocketnet-kismet.gpg] https://www.kismetwireless.net/repos/apt/release/%s %s main\n' \
    "$KISMET_CHANNEL" "$KISMET_CHANNEL" > "$root/etc/apt/sources.list.d/pocketnet-kismet.list"
arm apt-get -o Acquire::Retries=2 -o Acquire::Languages=none -o APT::Update::Error-Mode=any update
mapfile -t packages < "$config/packages.txt"
if [[ "$include_mdk4" == true ]]; then
    packages+=(mdk4)
fi
if [[ "$(arm dpkg-query -W -f='${db:Status-Abbrev}' linux-firmware 2>/dev/null)" != 'ii ' ]]; then
    packages+=(linux-firmware)
fi
arm apt-get -o Dpkg::Use-Pty=0 install -y --no-install-recommends "${packages[@]}" kismet-core kismet-capture-linux-wifi \
    "python$PYTHON_VERSION=$PYTHON_PACKAGE_VERSION" "python$PYTHON_VERSION-venv=$PYTHON_PACKAGE_VERSION"
arm "python$PYTHON_VERSION" -m venv /opt/pocketnet/python
arm /opt/pocketnet/python/bin/python -m pip install --no-cache-dir --only-binary=:all: \
    'dbus-next==0.2.3' 'cryptography==45.0.7' 'qrcode==8.2' 'cffi==2.1.1' 'pycparser==3.12'
arm /opt/pocketnet/python/bin/python -c 'import cryptography, dbus_next, qrcode'
# Record the installed runtime set, then remove only build-specific packages.
arm dpkg-query -W -f='${binary:Package}\n' | sort -u > "$work/runtime-packages"
arm apt-get -o Dpkg::Use-Pty=0 install -y --no-install-recommends build-essential cmake ninja-build pkg-config file binutils \
    protobuf-compiler protobuf-compiler-grpc libprotobuf-dev libgrpc++-dev libssl-dev libsqlite3-dev \
    libcurl4-openssl-dev nlohmann-json3-dev
stage=$(mktemp -d "$repo/.dist.XXXXXXXX")
suffix="${commit:0:12}-jammy-arm64"
release="$stage/pocketnet-release-$suffix.tar.gz"
bash "$repo/scripts/build-arm64-release.sh" "$root" "$release" "$commit"
release_sha=$(sha256sum "$release" | cut -d' ' -f1)
bash "$repo/scripts/install-release.sh" --sha256 "$release_sha" --root "$root" "$release"
bash "$config/install-system.sh" "$root"
mdk4_status_path=/opt/pocketnet/deploy/mdk4-package-status
install -D -m 0755 "$repo/scripts/mdk4-package-status.sh" "$root$mdk4_status_path"
mdk4_status=$(arm "$mdk4_status_path")
if [[ "$include_mdk4" == true ]]; then
    jq -e '.status == "installed" and .architecture == "arm64"' <<< "$mdk4_status" >/dev/null
fi

kismet_version=$(arm dpkg-query -W -f='${Version}' kismet-core)
protobuf_version=$(arm pkg-config --modversion protobuf)
grpc_version=$(arm pkg-config --modversion grpc++)
python_version=$(arm /opt/pocketnet/python/bin/python -V)
arm dpkg-query -W -f='${binary:Package}\n' | sort -u > "$work/build-packages"
mapfile -t build_only < <(comm -13 "$work/runtime-packages" "$work/build-packages")
if ((${#build_only[@]})); then arm apt-get -o Dpkg::Use-Pty=0 purge -y "${build_only[@]}"; fi
umount "$root/var/cache/apt/archives"
arm apt-get clean
printf 'uninitialized\n' > "$root/etc/machine-id"
if [[ -f "$root/var/lib/dbus/machine-id" && ! -L "$root/var/lib/dbus/machine-id" ]]; then
    rm -f -- "$root/var/lib/dbus/machine-id"
fi
if [[ "$ENABLE_SSH" == true ]]; then
    bash "$config/configure-wired-ssh.sh" "$root" "$root/boot/firmware" "$public_key"
else
    systemctl --root="$root" disable ssh.service
fi
if [[ "$ENABLE_FIRST_BOOT" != true ]]; then
    systemctl --root="$root" disable pocketnet-firstboot.service
fi
for target in etc/resolv.conf usr/sbin/policy-rc.d; do
    rm -f -- "$root/$target"
    if [[ -e "$work/${target##*/}.original" || -L "$work/${target##*/}.original" ]]; then
        mv -- "$work/${target##*/}.original" "$root/$target"
    fi
done
sync -f "$image"
umount --recursive "$root"
fsck.vfat -n "${loop}p1"
e2fsck -fn "${loop}p2"
close_image
bash "$repo/scripts/verify-image.sh" "$image"
image_name="pocketnet-$suffix.img.xz"
xz -T2 -3 -c "$image" > "$stage/$image_name"
jq -n --arg git_commit "$commit" --arg ubuntu_release "$UBUNTU_RELEASE" --arg base_image "$base" \
    --arg base_sha256 "$base_sha" --arg arch "$UBUNTU_ARCH" --arg python "$python_version" \
    --arg kismet "$kismet_version" --arg build_type "$BUILD_TYPE" --arg protobuf "$protobuf_version" \
    --arg grpc "$grpc_version" --arg generated_at "$(date -u +%FT%TZ)" --argjson mdk4 "$mdk4_status" \
    --arg image "$image_name" --arg release "$(basename "$release")" --arg release_sha256 "$release_sha" \
    '$ARGS.named' > "$stage/manifest.json"
(cd "$stage" && sha256sum "$image_name" "$(basename "$release")" manifest.json > SHA256SUMS)
chmod 0755 "$stage"
chmod 0644 "$stage/$image_name" "$release" "$stage/manifest.json" "$stage/SHA256SUMS"
if [[ -e "$repo/dist" || -L "$repo/dist" ]]; then
    [[ -d "$repo/dist" && ! -L "$repo/dist" ]]
    old=$(mktemp -d "$repo/.dist-previous.XXXXXXXX")
    rmdir "$old"
    mv -T -- "$repo/dist" "$old"
    previous="$old"
fi
mv -T -- "$stage" "$repo/dist"
stage=
if [[ -n "$previous" ]]; then rm -r -- "$previous"; previous=; fi
echo "Image and release ready: $repo/dist"
