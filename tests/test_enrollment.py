"""V0.3 acceptance cases that can be exercised without a radio or phone."""

import hmac
import json
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from cryptography.hazmat.primitives import hashes, serialization
from cryptography import x509
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from dbus_next import DBusError, Variant

from raspberry.enrollment.authority import Authority
from raspberry.enrollment.admin import initialize
from raspberry.enrollment.gatt import Enrollment
from raspberry.enrollment.protocol import (
    REQUEST_DOMAIN, RESPONSE_KEY, b64, decode, load_public, public_bytes, qr_key, transcript,
)
from raspberry.enrollment.registry import Registry
from raspberry.time_sync.ble_server import TimeSync
from raspberry.time_sync.protocol import PROBE, REQUEST, STATUS

QR_SECRET = b"q" * 32
RADIO = "/org/bluez/hci0"
FIRST = RADIO + "/dev_00_11_22_33_44_55"
SECOND = RADIO + "/dev_00_11_22_33_44_66"


class EnrollmentAcceptance(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name)
        key = ec.generate_private_key(ec.SECP256R1())
        (self.state / "device.key").write_bytes(key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption(),
        ))
        (self.state / "authority.json").write_text(json.dumps({
            "device_id": "piagent-test", "ssid": "PiAgent", "telemetry_url": "https://127.0.0.1:9443",
            "ca_pem": "test CA", "enrollment_verifier": b64(qr_key(QR_SECRET)),
            "api_secret": b64(b"a" * 32), "wifi_secret": b64(b"w" * 32),
        }), encoding="utf-8")
        self.registry = Registry(self.state / "devices.sqlite3")
        self.registry.initialize()
        self.authority = Authority(self.state)
        self.service = Enrollment(self.authority, RADIO, "/service1")
        self.phone = ec.generate_private_key(ec.SECP256R1())
        self.psks = {}
        mock = patch("raspberry.enrollment.authority.wifi_request", side_effect=self.wifi)
        mock.start()
        self.addCleanup(mock.stop)

    def wifi(self, op, wifi_id, psk=None):
        if op == "set":
            self.psks[wifi_id] = psk
        else:
            self.psks.pop(wifi_id, None)

    def request(self, path, *, phone=None, secret=QR_SECRET, mode="register"):
        source = json.loads(self.service.challenge(path, 0))
        phone = phone or self.phone
        transient = ec.generate_private_key(ec.SECP256R1())
        public, ephemeral = b64(public_bytes(phone.public_key())), b64(public_bytes(transient.public_key()))
        frame = transcript(
            REQUEST_DOMAIN, self.authority.device_id, source["nonce"], source["ephemeral"],
            mode, public, ephemeral, b64(b"test phone"),
        )
        packet = json.dumps({
            "mode": mode, "nonce": source["nonce"], "device_name": "test phone", "public_key": public,
            "ephemeral": ephemeral, "proof": b64(hmac.digest(qr_key(secret), frame, "sha256")) if mode == "register" else "",
            "signature": b64(phone.sign(frame, ec.ECDSA(hashes.SHA256()))),
        }).encode("ascii")
        derived = HKDF(algorithm=hashes.SHA256(), length=32, salt=decode(source["nonce"], 32), info=RESPONSE_KEY).derive(
            transient.exchange(ec.ECDH(), load_public(decode(source["ephemeral"], 65)))
        )

        def open_response(sealed):
            return json.loads(AESGCM(derived).decrypt(sealed[:12], sealed[12:], frame))

        return packet, open_response

    async def submit(self, path, data):
        await self.service.submit(path, b"\x01")
        for start in range(0, len(data), 19):
            await self.service.submit(path, b"\x02" + data[start:start + 19])
        await self.service.submit(path, b"\x03")

    async def register(self, path=FIRST, **options):
        request, decrypt = self.request(path, **options)
        await self.submit(path, request)
        grant = await self.service.grant(path)
        self.assertIsNotNone(grant)
        return decrypt(grant.sealed)

    async def test_r1_correct_qr_registers_and_seals_credentials(self):
        issuer = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, "PiAgent test CA")])
        now = datetime.now(timezone.utc)
        ca = (x509.CertificateBuilder().subject_name(issuer).issuer_name(issuer)
              .public_key(self.phone.public_key()).serial_number(x509.random_serial_number())
              .not_valid_before(now - timedelta(days=1)).not_valid_after(now + timedelta(days=1))
              .sign(self.phone, hashes.SHA256()))
        ca_file = self.state / "ca.pem"
        ca_file.write_bytes(ca.public_bytes(serialization.Encoding.PEM))
        provisioned, qr = self.state / "provisioned", self.state / "enrollment.svg"
        with patch("raspberry.enrollment.admin.secrets.token_bytes", side_effect=[QR_SECRET, b"a" * 32, b"w" * 32]):
            initialize(SimpleNamespace(state=provisioned, qr_file=qr, ca_file=ca_file,
                telemetry_url="https://127.0.0.1:9443", device_id="piagent-test", ssid="PiAgent"))
        self.assertIn(b"<svg", qr.read_bytes())
        self.authority = Authority(provisioned)
        self.registry = self.authority.registry
        self.service = Enrollment(self.authority, RADIO, "/service1")
        profile = await self.register()
        self.assertEqual(self.registry.authorize(profile["token"]), profile["device_id"])
        self.assertIn(profile["psk"], self.psks.values())

    async def test_r2_incorrect_secret_rejected(self):
        packet, _ = self.request(FIRST, secret=b"x" * 32)
        await self.submit(FIRST, packet)
        self.assertEqual(self.service.result(FIRST), b"\x02\x00\x00")
        self.assertEqual(self.registry.list_devices(), [])

    async def test_r3_used_and_replaced_challenge_rejected(self):
        packet, _ = self.request(FIRST)
        await self.submit(FIRST, packet)
        with self.assertRaises(DBusError):
            await self.submit(FIRST, packet)
        self.service.challenge(FIRST, 0)
        await self.submit(FIRST, packet)
        self.assertIsNone(await self.service.grant(FIRST))
        self.assertEqual(len(self.registry.list_devices()), 1)

    async def test_r4_signed_reconnect_keeps_identity(self):
        initial = await self.register()
        before = self.registry.database.stat().st_mtime_ns
        self.service.disconnect(FIRST)
        resumed = await self.register(SECOND, mode="resume")
        self.assertEqual(initial["device_id"], resumed["device_id"])
        self.assertEqual(initial["psk"], resumed["psk"])
        self.assertEqual(self.registry.database.stat().st_mtime_ns, before)
        self.assertEqual(len(self.registry.list_devices()), 1)

    async def test_r5_registry_survives_service_recreation(self):
        profile = await self.register()
        fresh = Authority(self.state)
        self.assertEqual(fresh.registry.authorize(profile["token"]), profile["device_id"])

    async def test_b1_unregistered_device_has_no_ble_grant(self):
        self.service.challenge(FIRST, 0)
        self.assertIsNone(await self.service.grant(FIRST))
        sync = TimeSync(None, ":1.5", RADIO, "", self.service)
        with self.assertRaises(DBusError):
            await sync.authorize({"device": Variant("o", FIRST)})

    async def test_b2_other_peer_cannot_obtain_sensitive_result(self):
        await self.register()
        self.service.challenge(SECOND, 0)
        self.assertEqual(self.service.result(SECOND), b"\x00\x00\x00")
        with self.assertRaises(DBusError):
            await self.service.submit(SECOND, b"\x04\x00\x00")

    async def test_b3_registered_device_has_ble_grant(self):
        profile = await self.register()
        grant = await self.service.grant(FIRST)
        self.assertEqual(grant.ble_key, decode(profile["ble_key"], 32))
        sync = TimeSync(None, ":1.5", RADIO, "", self.service)
        options = {"device": Variant("o", FIRST)}
        await sync.authorize(options)
        _, _, nonce = STATUS.unpack(sync.status())
        packet = REQUEST.pack(PROBE, nonce, 1, 1_800_000_000_000)
        mac = hmac.digest(grant.ble_key, b"piagent/time-sync/request/v3" + packet, "sha256")[:8]
        await sync.submit(packet[:1] + mac + packet[9:], options, (1_800_000_000_400, 100))
        self.assertEqual(sync.session.probes[1].t2, 1_800_000_000_400)

    async def test_d4_other_device_remains_active(self):
        first = await self.register()
        second = await self.register(SECOND, phone=ec.generate_private_key(ec.SECP256R1()))
        self.assertNotEqual(first["psk"], second["psk"])
        self.registry.revoke(first["device_id"], lambda wifi_id: self.wifi("revoke", wifi_id))
        self.assertEqual(self.registry.authorize(second["token"]), second["device_id"])
        self.assertIsNotNone(await self.service.grant(SECOND))
