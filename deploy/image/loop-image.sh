#!/usr/bin/env bash
# Common loop helpers for a private, regular image file.
open_image() {
    local layout
    [[ -f "$image" && ! -L "$image" ]] || { echo 'Expected a regular IMG file.' >&2; return 1; }
    layout=$(sfdisk --json "$image")
    jq -e '.partitiontable.partitions | length == 2' <<< "$layout" >/dev/null
    [[ -z "$(losetup -j "$image")" ]] || { echo "$image already has a loop device." >&2; return 1; }
    loop=$(losetup --find --show --partscan --nooverlap "$@" "$image")
    local tries
    for tries in {1..30}; do
        [[ -b "${loop}p1" && -b "${loop}p2" ]] && break
        sleep 0.2
    done
    [[ "$(blkid -s TYPE -o value "${loop}p1")" == vfat &&
       "$(blkid -s TYPE -o value "${loop}p2")" == ext4 ]]
}

close_image() {
    if [[ -n "${root:-}" ]] && mountpoint -q "$root"; then umount --recursive "$root" || return 1; fi
    if [[ -n "${loop:-}" ]]; then
        losetup -d "$loop" || return 1
        loop=
    fi
}
