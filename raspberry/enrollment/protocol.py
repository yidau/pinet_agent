"""Wire encoding and cryptography shared by the BLE registration service."""

import base64
import hashlib
import hmac
import re
import secrets

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

VERSION = 1
SERVICE = "7ab410a0-fd6a-49f1-91bb-40e71e672100"
INFO, CHALLENGE, REQUEST, RESULT = (SERVICE[:-2] + f"{i:02x}" for i in range(1, 5))
CHALLENGE_DOMAIN = "piagent/enrollment/challenge/v1"
REQUEST_DOMAIN = "piagent/enrollment/request/v1"
ENROLLMENT_KEY = b"piagent/enrollment/key/v1"
RESPONSE_KEY = b"piagent/enrollment/response/v1"
CLOCK_REQUEST = b"piagent/time-sync/request/v3"


def b64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def decode(value: str, size: int | None = None) -> bytes:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", value):
        raise ValueError("Invalid binary field")
    decoded = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    if b64(decoded) != value or (size is not None and len(decoded) != size):
        raise ValueError("Invalid binary field length")
    return decoded


def public_bytes(key: ec.EllipticCurvePublicKey) -> bytes:
    return key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


def load_public(value: bytes) -> ec.EllipticCurvePublicKey:
    if len(value) != 65 or value[0] != 4:
        raise ValueError("Expected a P-256 uncompressed public key")
    return ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), value)


def fingerprint(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def transcript(*parts: str) -> bytes:
    return "\n".join(parts).encode("ascii")


def qr_key(secret: bytes) -> bytes:
    return hmac.digest(secret, ENROLLMENT_KEY, "sha256")


def protect_response(
    ephemeral: ec.EllipticCurvePrivateKey,
    client: ec.EllipticCurvePublicKey,
    salt: bytes,
    associated: bytes,
    plaintext: bytes,
) -> bytes:
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=RESPONSE_KEY).derive(
        ephemeral.exchange(ec.ECDH(), client)
    )
    iv = secrets.token_bytes(12)
    return iv + AESGCM(key).encrypt(iv, plaintext, associated)
