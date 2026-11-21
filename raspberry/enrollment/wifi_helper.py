"""Manage only PiAgent hostapd PSKs through a local, authenticated socket."""

import base64
import json
import logging
import os
import re
import socket
import stat
import struct
import tempfile
import time
from pathlib import Path


LOG = logging.getLogger("piagent.enrollment.wifi")
PSK_FILE = Path("/var/lib/piagent-enrollment/hostapd.psk")
HOSTAPD_CONFIG = Path("/etc/hostapd/piagent.conf")
HOSTAPD_SOCKET = Path("/run/hostapd/wlan0")
RUNTIME_DIR = Path("/run/piagent-enrollment-wifi")
WILDCARD_MAC = "00:00:00:00:00:00"
CREDENTIAL_ID = re.compile(r"[0-9a-f]{32}")
PASSPHRASE = re.compile(r"[A-Za-z0-9_-]{8,63}")
KEY_ID = re.compile(r"[A-Za-z0-9_-]{22}")
PEER_CREDENTIALS = struct.Struct("3i")
REQUEST_BYTES = 512
RETRY_SECONDS = 5


class WifiError(Exception):
    """The credential change could not be confirmed."""


def hostapd_key_id(credential_id: str) -> str:
    # hostapd's keyid field has space for 31 characters plus a NUL.
    return base64.urlsafe_b64encode(bytes.fromhex(credential_id)).decode("ascii").rstrip("=")


def config_fields(config: str) -> dict[str, str]:
    fields = {}
    for line in config.splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key in fields:
            raise WifiError("Unexpected hostapd configuration")
        fields[key] = value
    return fields


class Hostapd:
    def __init__(self, config: Path, endpoint: Path, runtime_dir: Path, psk_file: Path):
        self.config = config
        self.endpoint = endpoint
        self.runtime_dir = runtime_dir
        self.psk_file = psk_file

    def _request(self, message: bytes) -> bytes:
        with tempfile.TemporaryDirectory(dir=self.runtime_dir, prefix="ctrl-") as directory:
            with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as channel:
                channel.settimeout(2)
                channel.bind(os.path.join(directory, "reply"))
                channel.connect(os.fspath(self.endpoint))
                channel.sendall(message)
                return channel.recv(4096)

    def check_config(self) -> None:
        settings = config_fields(self.config.read_text(encoding="ascii"))
        required = {
            "interface": self.endpoint.name,
            "driver": "nl80211",
            "ctrl_interface": str(self.endpoint.parent),
            "ctrl_interface_group": "0",
            "ssid": "PiAgent",
            "wpa": "2",
            "wpa_key_mgmt": "WPA-PSK",
            "rsn_pairwise": "CCMP",
            "wpa_psk_file": str(self.psk_file),
            "disable_pmksa_caching": "1",
        }
        if (
            any(settings.get(name) != value for name, value in required.items())
            or settings.keys() & {"bss", "wpa_passphrase", "wpa_psk", "wpa_psk_radius"}
            or any(settings.get(name, "0") != "0" for name in ("wps_state", "okc", "rsn_preauth"))
        ):
            raise WifiError("PiAgent hotspot credential configuration is not active")

        active = config_fields(self._request(b"GET_CONFIG").decode("ascii"))
        if (
            active.get("ssid") != required["ssid"]
            or active.get("wpa") != required["wpa"]
            or active.get("key_mgmt", "").split() != [required["wpa_key_mgmt"]]
            or active.get("rsn_pairwise_cipher") != required["rsn_pairwise"]
            or active.get("wps_state", "disabled") != "disabled"
            or active.keys() & {"passphrase", "psk"}
        ):
            raise WifiError("Active hostapd is not the PiAgent WPA2 hotspot")

    def reload_psks(self) -> None:
        # hostapd 2.10 checks negotiated PMKs and deauthenticates mismatches.
        # It retains connections using the other installed PSKs.
        if self._request(b"RELOAD_WPA_PSK").strip() != b"OK":
            raise WifiError("Hostapd did not confirm credential reload")


class PskFile:
    def __init__(self, path: Path):
        self.path = path

    def read(self) -> dict[str, str]:
        directory = self.path.parent.lstat()
        if not stat.S_ISDIR(directory.st_mode) or directory.st_uid != os.geteuid() or directory.st_mode & 0o077:
            raise WifiError("Hostapd credential directory is not private")
        try:
            info = self.path.lstat()
        except FileNotFoundError:
            return {}
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077:
            raise WifiError("Hostapd credential file is not private")
        credentials = {}
        for line in self.path.read_text(encoding="ascii").splitlines():
            if not line or line.startswith("#"):
                continue
            fields = line.split(" ")
            if len(fields) != 3:
                raise WifiError("Invalid hostapd credential entry")
            identifier, mac, psk = fields
            key_id = identifier.removeprefix("keyid=")
            if (
                not identifier.startswith("keyid=")
                or not KEY_ID.fullmatch(key_id)
                or mac != WILDCARD_MAC
                or not PASSPHRASE.fullmatch(psk)
                or key_id in credentials
            ):
                raise WifiError("Invalid hostapd credential entry")
            credentials[key_id] = psk
        if len(set(credentials.values())) != len(credentials):
            raise WifiError("Hostapd credential file contains a shared key")
        return credentials

    def replace(self, entries: dict[str, str]) -> None:
        descriptor, temporary_path = tempfile.mkstemp(dir=self.path.parent, prefix=".hostapd-")
        try:
            with os.fdopen(descriptor, "w", encoding="ascii", newline="\n") as output:
                for key_id, psk in sorted(entries.items()):
                    output.write(f"keyid={key_id} {WILDCARD_MAC} {psk}\n")
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary_path, self.path)
            directory = os.open(self.path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            Path(temporary_path).unlink(missing_ok=True)


class WifiCredentials:
    def __init__(self, store: PskFile, access_point: Hostapd):
        self.store = store
        self.access_point = access_point
        self.reload_pending = True

    def synchronize(self) -> None:
        self.store.read()
        self.access_point.check_config()
        self.access_point.reload_psks()
        self.reload_pending = False

    def update(self, operation: str, credential_id: str, psk: str | None) -> None:
        entries = self.store.read()
        key_id = hostapd_key_id(credential_id)
        previous = entries.get(key_id)
        if operation == "revoke":
            self.reload_pending = True
            if previous is not None:
                del entries[key_id]
                self.store.replace(entries)
            # Keep the disabled credential off disk if the daemon is unavailable.
            self.synchronize()
            return

        if operation != "set" or psk is None:
            raise WifiError("Invalid credential operation")
        self.access_point.check_config()
        if previous is not None and previous != psk:
            raise WifiError("A credential ID already has a different key")
        if previous is None and psk in entries.values():
            raise WifiError("A key may be assigned to only one credential")
        self.reload_pending = True
        if previous is None:
            entries[key_id] = psk
            self.store.replace(entries)
        try:
            self.access_point.reload_psks()
        except (WifiError, OSError):
            if previous is None:
                del entries[key_id]
                self.store.replace(entries)
            raise
        self.reload_pending = False


def parse_request(data: bytes) -> tuple[str, str, str | None]:
    request = json.loads(data)
    if not isinstance(request, dict):
        raise WifiError("Expected an object")
    operation = request.get("op")
    identifier = request.get("credential_id")
    if not isinstance(identifier, str) or not CREDENTIAL_ID.fullmatch(identifier):
        raise WifiError("Invalid credential ID")
    if operation == "revoke" and request.keys() == {"op", "credential_id"}:
        return operation, identifier, None
    if operation == "set" and request.keys() == {"op", "credential_id", "psk"}:
        psk = request["psk"]
        if isinstance(psk, str) and PASSPHRASE.fullmatch(psk):
            return operation, identifier, psk
    raise WifiError("Invalid credential operation")


def read_request(channel: socket.socket) -> bytes:
    deadline = time.monotonic() + 2
    data = bytearray()
    while len(data) < REQUEST_BYTES:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        channel.settimeout(remaining)
        chunk = channel.recv(REQUEST_BYTES - len(data))
        if not chunk:
            break
        data.extend(chunk)
        if data.endswith(b"\n"):
            return bytes(data[:-1])
    raise WifiError("Incomplete credential request")


def handle_request(channel: socket.socket, allowed_uid: int, manager: WifiCredentials) -> None:
    credentials = channel.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, PEER_CREDENTIALS.size)
    _pid, uid, _gid = PEER_CREDENTIALS.unpack(credentials)
    if uid != allowed_uid:
        return
    try:
        manager.update(*parse_request(read_request(channel)))
    except (OSError, WifiError, ValueError):
        LOG.warning("Wi-Fi credential change could not be confirmed")
        reply = b'{"ok":false}\n'
    else:
        reply = b'{"ok":true}\n'
    channel.settimeout(2)
    channel.sendall(reply)


def main() -> None:
    import pwd

    logging.basicConfig(level=logging.INFO)
    if os.environ.get("LISTEN_PID") != str(os.getpid()) or os.environ.get("LISTEN_FDS") != "1":
        raise SystemExit("Run this service through piagent-enrollment-wifi.socket")
    allowed_uid = pwd.getpwnam("piagent-ble").pw_uid
    access_point = Hostapd(HOSTAPD_CONFIG, HOSTAPD_SOCKET, RUNTIME_DIR, PSK_FILE)
    manager = WifiCredentials(PskFile(PSK_FILE), access_point)
    with socket.socket(fileno=3) as listener:
        while True:
            listener.settimeout(RETRY_SECONDS if manager.reload_pending else None)
            try:
                channel, _address = listener.accept()
            except TimeoutError:
                try:
                    manager.synchronize()
                except (OSError, WifiError, ValueError):
                    pass
                continue

            with channel:
                try:
                    handle_request(channel, allowed_uid, manager)
                except OSError:
                    LOG.info("Wi-Fi credential socket closed before the reply")


if __name__ == "__main__":
    main()
