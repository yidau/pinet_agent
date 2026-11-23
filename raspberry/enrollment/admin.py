"""Local administrator CLI for provisioning and revoking BLE enrollments."""

import argparse
import json
import os
import re
import secrets
import stat
from pathlib import Path
from urllib.parse import urlparse

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from .authority import wifi_request
from .protocol import SERVICE, VERSION, b64, fingerprint, public_bytes, qr_key
from .registry import Registry

DEFAULT_STATE = Path("/var/lib/piagent-devices")


def initialize(args: argparse.Namespace) -> None:
    import qrcode
    from qrcode.image.svg import SvgPathImage

    state = args.state
    url = urlparse(args.telemetry_url)
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or url.query or url.fragment or url.path not in ("", "/") or url.port != 9443):
        raise ValueError("Use the HTTPS gRPC telemetry endpoint on port 9443")
    if not 1 <= len(args.ssid.encode("utf-8")) <= 32 or not args.ssid.isprintable():
        raise ValueError("Invalid hotspot name")
    ca_pem = args.ca_file.read_text(encoding="ascii")
    if len(ca_pem) > 4096:
        raise ValueError("Use the PiAgent CA certificate")
    x509.load_pem_x509_certificate(ca_pem.encode("ascii"))
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", args.device_id):
        raise ValueError("Invalid Pi identifier")
    if args.qr_file.is_relative_to(state) or args.qr_file.resolve().is_relative_to(state.resolve()):
        raise ValueError("Keep the permanent QR outside the device registry")
    state.mkdir(mode=0o750, parents=True, exist_ok=True)
    if any((state / name).exists() for name in ("device.key", "authority.json", "devices.sqlite3")) or args.qr_file.exists():
        raise ValueError("An enrollment identity or QR already exists")
    if os.name == "posix" and stat.S_IMODE(state.stat().st_mode) & 0o027:
        raise ValueError("Registry directory permissions are too broad")
    secret = secrets.token_bytes(32)
    device_key = ec.generate_private_key(ec.SECP256R1())
    config = {
        "device_id": args.device_id, "ssid": args.ssid, "telemetry_url": args.telemetry_url, "ca_pem": ca_pem,
        "enrollment_verifier": b64(qr_key(secret)), "api_secret": b64(secrets.token_bytes(32)),
        "wifi_secret": b64(secrets.token_bytes(32)),
    }
    qr = {
        "version": VERSION, "device_id": args.device_id, "enrollment_secret": b64(secret),
        "public_key_fingerprint": fingerprint(public_bytes(device_key.public_key())), "ble_service": SERVICE,
    }
    image = qrcode.make(json.dumps(qr, separators=(",", ":")), image_factory=SvgPathImage)
    created = []
    database = state / "devices.sqlite3"
    try:
        for path, value, mode in (
            (state / "device.key", device_key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()), 0o600),
            (state / "authority.json", json.dumps(config, separators=(",", ":")).encode("utf-8"), 0o600),
            (database, b"", 0o640),
        ):
            with os.fdopen(os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode), "wb") as output:
                created.append(path)
                output.write(value)
        Registry(database).initialize()
        with os.fdopen(os.open(args.qr_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "wb") as output:
            created.append(args.qr_file)
            image.save(output)
    except BaseException:
        for path in reversed(created):
            path.unlink(missing_ok=True)
        raise
    print(f"Saved permanent enrollment QR to {args.qr_file}")


def main() -> None:
    os.umask(0o027)
    parser = argparse.ArgumentParser(description="Manage PiAgent enrolled devices locally")
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE)
    commands = parser.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init")
    for option in ("device-id", "ssid", "telemetry-url"):
        init.add_argument(f"--{option}", required=True)
    for option in ("ca-file", "qr-file"):
        init.add_argument(f"--{option}", required=True, type=Path)
    commands.add_parser("list")
    revoke = commands.add_parser("revoke")
    revoke.add_argument("device_id")
    setting = commands.add_parser("registration")
    setting.add_argument("mode", choices=("on", "off"))
    args = parser.parse_args()
    registry = Registry(args.state / "devices.sqlite3")
    try:
        if args.command == "init":
            initialize(args)
        elif args.command == "list":
            print(json.dumps(registry.list_devices(), ensure_ascii=False, indent=2))
        elif args.command == "revoke":
            if not re.fullmatch(r"[0-9a-f]{32}", args.device_id) or not registry.revoke(args.device_id, lambda wifi_id: wifi_request("revoke", wifi_id)):
                parser.error("Unknown device")
            print("Device and hotspot credential revoked")
        else:
            registry.allow_registration(args.mode == "on")
            print(f"Registration {args.mode}")
    except (OSError, ValueError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
