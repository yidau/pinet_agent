"""Authorize new phones and return credentials only in a sealed BLE response."""

import hashlib
import hmac
import json
import secrets
import socket
import time
from dataclasses import dataclass
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

from .protocol import (
    CHALLENGE_DOMAIN, REQUEST_DOMAIN, VERSION, b64, decode, fingerprint,
    load_public, protect_response, public_bytes, transcript,
)
from .registry import Registry

WIFI_SOCKET = "/run/piagent-enrollment-wifi.sock"
CHALLENGE_TTL = 60


def wifi_request(op: str, credential_id: str, psk: str | None = None) -> None:
    request = {"op": op, "credential_id": credential_id}
    if psk is not None:
        request["psk"] = psk
    # Keep the privileged helper independent of BlueZ and of the device registry.
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(6)
        client.connect(WIFI_SOCKET)
        client.sendall(json.dumps(request, separators=(",", ":")).encode("ascii") + b"\n")
        with client.makefile("rb") as reply:
            accepted = json.loads(reply.readline(512))
    if not isinstance(accepted, dict) or accepted.get("ok") is not True:
        raise ValueError("Hotspot credential update was rejected")


@dataclass
class Challenge:
    nonce: bytes
    ephemeral: ec.EllipticCurvePrivateKey
    opened: float
    description: bytes

    @property
    def expired(self) -> bool:
        return time.monotonic() - self.opened >= CHALLENGE_TTL


@dataclass
class Grant:
    device_id: str
    ble_key: bytes
    sealed: bytes


class Authority:
    def __init__(self, state: Path) -> None:
        config = json.loads((state / "authority.json").read_text(encoding="utf-8"))
        self.device_id = config["device_id"]
        self.ssid = config["ssid"]
        self.mcp_url = config["mcp_url"]
        self.ca_pem = config["ca_pem"]
        self.enrollment_verifier = decode(config["enrollment_verifier"], 32)
        self.api_secret = decode(config["api_secret"], 32)
        self.wifi_secret = decode(config["wifi_secret"], 32)
        self.private_key = serialization.load_pem_private_key((state / "device.key").read_bytes(), password=None)
        if not isinstance(self.private_key, ec.EllipticCurvePrivateKey) or not isinstance(self.private_key.curve, ec.SECP256R1):
            raise ValueError("Invalid device identity key")
        public = public_bytes(self.private_key.public_key())
        self.description = json.dumps({
            "version": VERSION, "device_id": self.device_id,
            "public_key": b64(public), "public_key_fingerprint": fingerprint(public),
        }, separators=(",", ":")).encode("ascii")
        self.registry = Registry(state / "devices.sqlite3")

    def challenge(self) -> Challenge:
        nonce, ephemeral = secrets.token_bytes(32), ec.generate_private_key(ec.SECP256R1())
        public = b64(public_bytes(ephemeral.public_key()))
        signature = self.private_key.sign(transcript(CHALLENGE_DOMAIN, self.device_id, b64(nonce), public), ec.ECDSA(hashes.SHA256()))
        value = json.dumps({"nonce": b64(nonce), "ephemeral": public, "signature": b64(signature)}, separators=(",", ":"))
        return Challenge(nonce, ephemeral, time.monotonic(), value.encode("ascii"))

    def issue_token(self, device_id: str) -> str:
        return b64(hmac.digest(self.api_secret, device_id.encode("ascii"), "sha256"))

    def issue_psk(self, wifi_id: str) -> str:
        return b64(hmac.digest(self.wifi_secret, wifi_id.encode("ascii"), "sha256"))

    def register(self, challenge: Challenge, packet: bytes) -> Grant:
        if challenge.expired:
            raise ValueError("Expired BLE registration challenge")
        request = json.loads(packet)
        fields = {"mode", "nonce", "device_name", "public_key", "ephemeral", "proof", "signature"}
        if not isinstance(request, dict) or set(request) != fields or not all(isinstance(value, str) for value in request.values()):
            raise ValueError("Invalid registration frame")
        mode = request["mode"]
        name = request["device_name"].encode("utf-8")
        if mode not in ("register", "resume") or not 1 <= len(name) <= 64 or not request["device_name"].isprintable():
            raise ValueError("Invalid registration attributes")
        if not hmac.compare_digest(decode(request["nonce"], 32), challenge.nonce):
            raise ValueError("Invalid BLE registration challenge")
        public = decode(request["public_key"], 65)
        client = load_public(decode(request["ephemeral"], 65))
        associated = transcript(
            REQUEST_DOMAIN, self.device_id, request["nonce"], b64(public_bytes(challenge.ephemeral.public_key())),
            mode, request["public_key"], request["ephemeral"], b64(name),
        )
        if mode == "register":
            expected = hmac.digest(self.enrollment_verifier, associated, "sha256")
            if not hmac.compare_digest(decode(request["proof"], 32), expected):
                raise ValueError("Invalid registration authorization")
        elif request["proof"]:
            raise ValueError("Invalid resume proof")
        load_public(public).verify(decode(request["signature"]), associated, ec.ECDSA(hashes.SHA256()))
        phone = self.registry.activate(
            public, request["device_name"], register=(mode == "register"), issue_token=self.issue_token,
            enable_wifi=lambda wifi_id: wifi_request("set", wifi_id, self.issue_psk(wifi_id)),
        )
        device_id, ble_key = phone["device_id"], secrets.token_bytes(32)
        payload = json.dumps({
            "device_id": device_id, "token": self.issue_token(device_id), "ssid": self.ssid,
            "psk": self.issue_psk(phone["wifi_credential_id"]), "mcp_url": self.mcp_url,
            "ca_pem": self.ca_pem, "ble_key": b64(ble_key),
        }, separators=(",", ":")).encode("utf-8")
        sealed = protect_response(challenge.ephemeral, client, challenge.nonce, associated, payload)
        return Grant(device_id, ble_key, sealed)
