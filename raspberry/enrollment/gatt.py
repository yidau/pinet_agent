"""BlueZ transport for the registration protocol. Credentials stay encrypted on air."""

import asyncio
import re
import sqlite3
import time
from collections import deque
from dataclasses import dataclass, field

from cryptography.exceptions import InvalidSignature
from dbus_next import DBusError, PropertyAccess
from dbus_next.service import ServiceInterface, dbus_property, method

from .authority import Authority, Challenge, Grant
from .protocol import CHALLENGE, INFO, REQUEST, RESULT, SERVICE

GATT = "org.bluez.GattCharacteristic1"
MAX_PACKET = 1024
PAGE_SIZE = 17


def denied(reason: str = "NotAuthorized") -> DBusError:
    return DBusError(f"org.bluez.Error.{reason}", "Invalid or unauthorized enrollment operation")


@dataclass
class Peer:
    challenge: Challenge | None = None
    packet: bytearray = field(default_factory=bytearray)
    collecting: bool = False
    pending: bool = False
    failed: bool = False
    grant: Grant | None = None
    offset: int = 0


class Enrollment:
    def __init__(self, authority: Authority, adapter: str, service_path: str) -> None:
        self.authority = authority
        self.service_path = service_path
        self.device_path = re.compile(re.escape(adapter) + r"/dev_[0-9A-F_]+$")
        self.peers: dict[str, Peer] = {}
        self.failures: deque[float] = deque()

    def get_path(self, options: dict) -> str:
        path = options["device"].value if "device" in options else ""
        if not self.device_path.fullmatch(path) or ("link" in options and options["link"].value.upper() != "LE"):
            raise denied()
        return path

    def disconnect(self, path: str) -> None:
        self.peers.pop(path, None)

    async def grant(self, path: str) -> Grant | None:
        peer = self.peers.get(path)
        if peer is not None and peer.grant is not None:
            grant = peer.grant
            try:
                if await asyncio.to_thread(self.authority.registry.is_active, grant.device_id) and self.peers.get(path) is peer:
                    return grant
            except (sqlite3.Error, OSError):
                pass
        return None

    def challenge(self, path: str, offset: int) -> bytes:
        peer = self.peers.get(path)
        if peer is None:
            if len(self.peers) >= 16 or offset:
                raise denied("NotPermitted")
            peer = self.peers[path] = Peer()
        if peer.pending:
            raise denied("InProgress")
        if peer.challenge is None or peer.challenge.expired:
            if offset:
                raise denied("InvalidOffset")
            peer.challenge = self.authority.challenge()
            peer.collecting = False
        return peer.challenge.description

    def result(self, path: str) -> bytes:
        peer = self.peers.get(path)
        if peer is None:
            return b"\x00\x00\x00"
        if peer.pending:
            return b"\x03\x00\x00"
        if peer.failed:
            return b"\x02\x00\x00"
        if peer.grant is None:
            return b"\x00\x00\x00"
        sealed = peer.grant.sealed
        return b"\x01" + len(sealed).to_bytes(2, "big") + sealed[peer.offset:peer.offset + PAGE_SIZE]

    async def submit(self, path: str, value: bytes) -> None:
        peer = self.peers.get(path)
        if not value or len(value) > 20 or peer is None or peer.pending:
            raise denied("NotPermitted")
        opcode, data = value[0], value[1:]
        if opcode == 4 and len(data) == 2 and peer.grant is not None:
            offset = int.from_bytes(data, "big")
            if offset >= len(peer.grant.sealed):
                raise denied("InvalidOffset")
            peer.offset = offset
            return
        if peer.challenge is None or peer.challenge.expired:
            raise denied("NotPermitted")
        if opcode == 1 and not data:
            peer.packet.clear()
            peer.collecting = True
        elif opcode == 2 and data and peer.collecting and len(peer.packet) + len(data) <= MAX_PACKET:
            peer.packet.extend(data)
        elif opcode == 3 and not data and peer.collecting and peer.packet:
            await self.commit(path, peer)
        else:
            raise denied("InvalidValueLength")

    async def commit(self, path: str, peer: Peer) -> None:
        challenge, peer.challenge = peer.challenge, None
        packet = bytes(peer.packet)
        peer.packet.clear()
        peer.collecting = False
        peer.pending = True
        peer.failed = False
        peer.grant = None
        peer.offset = 0
        try:
            now = time.monotonic()
            while self.failures and now - self.failures[0] >= 60:
                self.failures.popleft()
            if challenge is None or len(self.failures) >= 8:
                peer.failed = True
                return
            # Count in-flight attempts as well so concurrent connections cannot bypass the limit.
            self.failures.append(now)
            try:
                grant = await asyncio.to_thread(self.authority.register, challenge, packet)
            except (InvalidSignature, ValueError, OSError, sqlite3.Error):
                peer.failed = True
                return
            if now in self.failures:
                self.failures.remove(now)
            if self.peers.get(path) is peer:
                peer.grant = grant
        finally:
            peer.pending = False


class EnrollmentService(ServiceInterface):
    def __init__(self) -> None:
        super().__init__("org.bluez.GattService1")

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":
        return SERVICE

    @dbus_property(access=PropertyAccess.READ)
    def Primary(self) -> "b":
        return True


class EnrollmentCharacteristic(ServiceInterface):
    def __init__(self, enrollment: Enrollment, uuid: str) -> None:
        super().__init__(GATT)
        self.enrollment = enrollment
        self.uuid = uuid

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":
        return self.uuid

    @dbus_property(access=PropertyAccess.READ)
    def Service(self) -> "o":
        return self.enrollment.service_path

    @dbus_property(access=PropertyAccess.READ)
    def Flags(self) -> "as":
        return ["write"] if self.uuid == REQUEST else ["read"]

    @method()
    async def ReadValue(self, options: "a{sv}") -> "ay":
        path = self.enrollment.get_path(options)
        offset = options["offset"].value if "offset" in options else 0
        if self.uuid == INFO:
            data = self.enrollment.authority.description
        elif self.uuid == CHALLENGE:
            data = self.enrollment.challenge(path, offset)
        elif self.uuid == RESULT:
            data = self.enrollment.result(path)
            if data[0] == 1 and await self.enrollment.grant(path) is None:
                raise denied()
        else:
            raise denied("NotPermitted")
        if offset > len(data):
            raise denied("InvalidOffset")
        return data[offset:]

    @method()
    async def WriteValue(self, value: "ay", options: "a{sv}"):
        if self.uuid != REQUEST or ("offset" in options and options["offset"].value != 0):
            raise denied("NotPermitted")
        if ("prepare-authorize" in options and options["prepare-authorize"].value) or ("type" in options and options["type"].value != "request"):
            raise denied("NotSupported")
        await self.enrollment.submit(self.enrollment.get_path(options), value)
