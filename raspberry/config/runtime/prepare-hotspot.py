"""Prepare the private hotspot PSK file without replacing enrolled-phone keys."""

import os
from pathlib import Path
import stat


STATE = Path("/var/lib/piagent-enrollment")


def prepare(state=STATE):
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory = state.lstat()
    if (not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.geteuid()
            or directory.st_mode & 0o077):
        raise RuntimeError("Hotspot credential directory is not private")

    path = state / "hostapd.psk"
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        existing = path.lstat()
        if (not stat.S_ISREG(existing.st_mode) or existing.st_uid != os.geteuid()
                or existing.st_mode & 0o077):
            raise RuntimeError("Hotspot credential file is not private") from None
    else:
        # An empty WPA2 PSK file admits no phones. Enrollment installs each
        # phone's individual key later through the existing credential helper.
        os.close(descriptor)


if __name__ == "__main__":
    prepare()
