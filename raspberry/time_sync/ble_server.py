import argparse
import asyncio
import hashlib
import hmac
import logging
import re
import secrets
from dataclasses import dataclass, field
from pathlib import Path

from dbus_next import BusType, DBusError, Message, MessageType, PropertyAccess
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, dbus_property, method

from .protocol import (
    APPLY,
    APPLY_BACKWARD,
    CONFIRM_BACKWARD,
    DEVICE_UUID,
    FAILED,
    HELPER_REQUEST,
    HELPER_RESULT,
    NO_RESULT,
    OK,
    PENDING,
    PROBE,
    REJECTED,
    REQUEST,
    REQUEST_UUID,
    RESPONSE,
    RESPONSE_UUID,
    RESULT,
    RESULT_UUID,
    SERVICE_UUID,
    SESSION_MS,
    STATUS,
    STATUS_UUID,
    VERSION,
    mono_ms,
    now_ms,
    validate_sample,
)

BLUEZ = "org.bluez"
DEVICE_IFACE = "org.bluez.Device1"
GATT_IFACE = "org.bluez.GattCharacteristic1"
ADVERT_IFACE = "org.bluez.LEAdvertisement1"
MANAGER_IFACE = "org.freedesktop.DBus.ObjectManager"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"
DBUS = "org.freedesktop.DBus"
DBUS_PATH = "/org/freedesktop/DBus"
APP_PATH = "/net/piagent/time_sync"
SERVICE_PATH = APP_PATH + "/service0"
ENROLLMENT_PATH = APP_PATH + "/service1"
ADVERT_PATH = "/net/piagent/time_advertisement"
CLOCK_SOCKET = "/run/piagent-clock.sock"
PEER_FLAGS = ("Connected", "Paired", "Bonded", "Trusted")
LOG = logging.getLogger(__name__)


def ble_error(code: str, message: str) -> DBusError:
    return DBusError(f"{BLUEZ}.Error.{code}", message)


async def call(bus: MessageBus, destination: str, path: str, interface: str,
               member: str, signature: str = "", body: list | None = None) -> list:
    message = Message(
        destination=destination, path=path, interface=interface, member=member,
        signature=signature, body=body or [],
    )
    reply = await asyncio.wait_for(bus.call(message), timeout=5)
    if reply.message_type == MessageType.ERROR:
        raise DBusError(reply.error_name, reply.body[0] if reply.body else member)
    return reply.body


@dataclass
class Probe:
    t1: int
    t2: int
    tick2: int
    response: tuple[int, int] | None = None


@dataclass
class Session:
    nonce: int
    opened: int
    probes: dict[int, Probe] = field(default_factory=dict)
    confirm_id: int | None = None
    final: bool = False


class TimeSync:
    def __init__(self, bus: MessageBus, owner: str, adapter: str, peer: str, enrollment=None):
        self.bus = bus
        self.owner = owner
        self.adapter = adapter
        self.peer = peer
        self.enrollment = enrollment
        self.registered_device: str | None = None
        self.saved_results: dict[str, tuple[int, int, int, int]] = {}
        self.peer_path: str | None = None
        self.connection_epoch = 0
        self.session: Session | None = None
        self.last_result = (0, 0, NO_RESULT, 0)
        self.bluez_gone = asyncio.Event()

    def invalidate_session(self) -> None:
        self.connection_epoch += 1
        self.session = None

    def handle_message(self, message: Message) -> Message | None:
        # Only bluetoothd may supply a Device1 object path to application methods.
        if message.message_type == MessageType.METHOD_CALL and (
            message.interface == ADVERT_IFACE and message.path == ADVERT_PATH
            or message.interface == GATT_IFACE and message.path.startswith((SERVICE_PATH + "/", ENROLLMENT_PATH + "/"))
        ):
            if message.sender != self.owner:
                return Message.new_error(
                    message, "org.freedesktop.DBus.Error.AccessDenied",
                    "Only Bluetooth service callbacks are accepted",
                )
        if message.message_type != MessageType.SIGNAL:
            return None
        if self.enrollment is not None and message.sender == self.owner:
            if message.interface == PROPERTIES_IFACE and message.member == "PropertiesChanged" and message.body[0] == DEVICE_IFACE:
                changed, invalidated = message.body[1:]
                connected = changed.get("Connected")
                blocked = changed.get("Blocked")
                if (connected is not None and not connected.value) or (blocked is not None and blocked.value) or "Connected" in invalidated:
                    self.enrollment.disconnect(message.path)
            elif message.interface == MANAGER_IFACE and message.member == "InterfacesRemoved" and DEVICE_IFACE in message.body[1]:
                self.enrollment.disconnect(message.body[0])
        if (
            message.sender == DBUS and message.path == DBUS_PATH
            and message.interface == DBUS and message.member == "NameOwnerChanged"
            and message.body[:2] == [BLUEZ, self.owner]
        ):
            self.invalidate_session()
            self.bluez_gone.set()
        elif message.sender == self.owner and self.peer_path is not None:
            if (
                message.interface == PROPERTIES_IFACE
                and message.member == "PropertiesChanged"
                and message.path == self.peer_path and message.body[0] == DEVICE_IFACE
            ):
                changed, invalidated = message.body[1:]
                if any(name in invalidated for name in (*PEER_FLAGS, "Address", "Blocked", "Adapter")) or any(
                    name in changed and changed[name].value is not True for name in PEER_FLAGS
                ) or (
                    "Blocked" in changed and changed["Blocked"].value
                ) or (
                    self.enrollment is None and "Address" in changed and changed["Address"].value.upper() != self.peer
                ) or (
                    "Adapter" in changed and changed["Adapter"].value != self.adapter
                ):
                    self.invalidate_session()
            elif (
                message.interface == MANAGER_IFACE and message.member == "InterfacesRemoved"
                and message.body[0] == self.peer_path and DEVICE_IFACE in message.body[1]
            ):
                self.invalidate_session()
        return None

    async def authorize(self, options: dict) -> bytes | None:
        if options.get("offset") and options["offset"].value != 0:
            raise ble_error("InvalidOffset", "A complete frame is required")
        if "link" in options and options["link"].value.upper() != "LE":
            raise ble_error("NotAuthorized", "A Bluetooth LE link is required")
        path = options["device"].value if "device" in options else ""
        if not re.fullmatch(re.escape(self.adapter) + r"/dev_(?:[0-9A-F]{2}_){5}[0-9A-F]{2}", path):
            raise ble_error("NotAuthorized", "Enroll a bonded phone before synchronizing")
        if self.enrollment is not None:
            grant = await self.enrollment.grant(path)
            if grant is None or self.bluez_gone.is_set():
                raise ble_error("NotAuthorized", "Authenticate a registered phone before synchronizing")
            if self.peer_path != path or self.registered_device != grant.device_id:
                if self.last_result[2] == PENDING:
                    raise ble_error("InProgress", "Clock adjustment is in progress")
                if self.registered_device != grant.device_id:
                    if self.registered_device is not None:
                        self.saved_results[self.registered_device] = self.last_result
                    self.last_result = self.saved_results.pop(grant.device_id, (0, 0, NO_RESULT, 0))
                    self.registered_device = grant.device_id
                self.invalidate_session()
                self.peer_path = path
            return grant.ble_key
        if not self.peer:
            raise ble_error("NotAuthorized", "Enroll a bonded phone before synchronizing")

        epoch = self.connection_epoch
        try:
            [properties] = await call(
                self.bus, self.owner, path, PROPERTIES_IFACE, "GetAll", "s", [DEVICE_IFACE],
            )
        except (DBusError, TimeoutError):
            raise ble_error("NotAuthorized", "Cannot verify the Bluetooth peer") from None
        values = {name: variant.value for name, variant in properties.items()}
        if (
            self.bluez_gone.is_set() or epoch != self.connection_epoch
            or values.get("Address", "").upper() != self.peer
            or values.get("Adapter") != self.adapter or values.get("Blocked") is not False
            or not all(values.get(name) is True for name in PEER_FLAGS)
        ):
            raise ble_error("NotAuthorized", "A connected, trusted bond is required")
        if self.peer_path != path:
            self.invalidate_session()
            self.peer_path = path
        return None

    def active_session(self) -> Session:
        session = self.session
        if session is None or session.final or mono_ms() - session.opened >= SESSION_MS:
            raise ble_error("NotPermitted", "Read TimeStatus to start a new session")
        if self.last_result[2] == PENDING:
            raise ble_error("InProgress", "Clock adjustment is in progress")
        return session

    def status(self) -> bytes:
        if self.last_result[2] == PENDING:
            return STATUS.pack(VERSION, 1, self.last_result[0])
        session = self.session
        # Reading status before a new batch abandons any uncommitted probes.
        if session is None or session.final or session.probes or mono_ms() - session.opened >= SESSION_MS:
            nonce = secrets.randbits(64)
            while nonce in (0, self.last_result[0], session.nonce if session else 0):
                nonce = secrets.randbits(64)
            session = self.session = Session(nonce, mono_ms())
        return STATUS.pack(VERSION, 0, session.nonce)

    def read_probe(self) -> bytes:
        session = self.active_session()
        if not session.probes:
            raise ble_error("NotPermitted", "No probe to read")
        sample_id = max(session.probes)
        probe = session.probes[sample_id]
        if probe.response is None:
            probe.response = (now_ms(), mono_ms())
        return RESPONSE.pack(sample_id, probe.t2, probe.response[0])

    async def submit(self, value: bytes, options: dict, received: tuple[int, int]) -> None:
        ble_key = await self.authorize(options)
        if (
            ("prepare-authorize" in options and options["prepare-authorize"].value)
            or ("type" in options and options["type"].value != "request")
        ):
            raise ble_error("NotSupported", "Use one Write Request for the entire frame")
        if len(value) != REQUEST.size:
            raise ble_error("InvalidValueLength", "Invalid time-sync frame")
        opcode, nonce, sample_id, timestamp = REQUEST.unpack(value)
        session = self.active_session()
        if ble_key is None:
            valid_nonce = nonce == session.nonce
        else:
            raw = REQUEST.pack(opcode, session.nonce, sample_id, timestamp)
            expected = hmac.digest(ble_key, b"piagent/time-sync/request/v3" + raw, "sha256")[:8]
            valid_nonce = hmac.compare_digest(value[1:9], expected)
        if not valid_nonce or not 1 <= sample_id <= 5:
            raise ble_error("NotPermitted", "Invalid or stale request")

        if opcode == PROBE:
            if session.confirm_id is not None or sample_id <= max(session.probes, default=0):
                raise ble_error("NotPermitted", "Repeated or out-of-order probe")
            session.probes[sample_id] = Probe(timestamp, *received)
        elif opcode in (APPLY, APPLY_BACKWARD):
            await self.apply(session, sample_id, timestamp, opcode == APPLY_BACKWARD)
        else:
            raise ble_error("NotSupported", "Unknown time-sync operation")

    async def apply(self, session: Session, sample_id: int, t4: int, backward: bool) -> None:
        probe = session.probes.get(sample_id)
        if probe is None or probe.response is None:
            raise ble_error("NotPermitted", "The selected response has not been read")
        if session.confirm_id is not None and (session.confirm_id != sample_id or not backward):
            raise ble_error("NotPermitted", "Explicit backward confirmation is required")
        t3, tick3 = probe.response
        try:
            offset, delay = validate_sample(probe.t1, probe.t2, t3, t4)
        except ValueError:
            session.final = True
            self.last_result = (session.nonce, sample_id, REJECTED, 0)
            return
        if offset > 0 and not backward:
            session.confirm_id = sample_id
            self.last_result = (session.nonce, sample_id, CONFIRM_BACKWARD, 0)
            return

        packet = HELPER_REQUEST.pack(int(backward), probe.t1, probe.t2, t3, t4, probe.tick2, tick3)
        self.last_result = (session.nonce, sample_id, PENDING, 0)
        code, readback = await self.adjust_clock(session, packet)
        session.final = code != CONFIRM_BACKWARD
        if code == CONFIRM_BACKWARD:
            session.confirm_id = sample_id
        self.last_result = (session.nonce, sample_id, code, readback)
        LOG.info("Clock sync result=%d offset_ms=%d delay_ms=%d", code, offset, delay)

    async def adjust_clock(self, session: Session, packet: bytes) -> tuple[int, int]:
        writer = None
        try:
            async with asyncio.timeout(5):
                reader, writer = await asyncio.open_unix_connection(CLOCK_SOCKET)
                if self.enrollment is not None and await self.enrollment.grant(self.peer_path) is None:
                    return REJECTED, 0
                if (
                    self.session is not session
                    or mono_ms() - session.opened >= SESSION_MS
                    or self.bluez_gone.is_set()
                ):
                    return REJECTED, 0
                writer.write(packet)
                writer.write_eof()
                await writer.drain()
                code, readback = HELPER_RESULT.unpack(await reader.readexactly(HELPER_RESULT.size))
                if code == OK and readback > 0:
                    return OK, readback
                if code in (REJECTED, FAILED, CONFIRM_BACKWARD):
                    return code, 0
        except (OSError, TimeoutError, asyncio.IncompleteReadError) as exc:
            LOG.warning("Clock service did not return a confirmed result: %s", type(exc).__name__)
        finally:
            if writer is not None:
                writer.close()
        return FAILED, 0


class TimeService(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.GattService1")

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":
        return SERVICE_UUID

    @dbus_property(access=PropertyAccess.READ)
    def Primary(self) -> "b":
        return True


class TimeCharacteristic(ServiceInterface):
    def __init__(self, sync: TimeSync, uuid: str, identity: bytes):
        super().__init__(GATT_IFACE)
        self.sync = sync
        self.uuid = uuid
        self.identity = identity

    @dbus_property(access=PropertyAccess.READ)
    def UUID(self) -> "s":
        return self.uuid

    @dbus_property(access=PropertyAccess.READ)
    def Service(self) -> "o":
        return SERVICE_PATH

    @dbus_property(access=PropertyAccess.READ)
    def Flags(self) -> "as":
        if self.uuid == DEVICE_UUID:
            return ["read"]
        if self.sync.enrollment is not None:
            return ["write"] if self.uuid == REQUEST_UUID else ["read"]
        if self.uuid == REQUEST_UUID:
            return ["encrypt-authenticated-write"]
        return ["encrypt-authenticated-read"]

    @method()
    async def ReadValue(self, options: "a{sv}") -> "ay":
        if self.uuid == DEVICE_UUID:
            offset = options["offset"].value if "offset" in options else 0
            if offset > len(self.identity):
                raise ble_error("InvalidOffset", "Offset outside device identity")
            return self.identity[offset:]
        if self.uuid == REQUEST_UUID:
            raise ble_error("NotPermitted", "TimeSyncRequest is write-only")
        await self.sync.authorize(options)
        if self.uuid == STATUS_UUID:
            return self.sync.status()
        if self.uuid == RESPONSE_UUID:
            return self.sync.read_probe()
        return RESULT.pack(*self.sync.last_result)

    @method()
    async def WriteValue(self, value: "ay", options: "a{sv}"):
        received = now_ms(), mono_ms()
        if self.uuid != REQUEST_UUID:
            raise ble_error("NotPermitted", "Characteristic is read-only")
        await self.sync.submit(value, options, received)


class Advertisement(ServiceInterface):
    def __init__(self, sync: TimeSync, advertised_service: str = SERVICE_UUID):
        super().__init__(ADVERT_IFACE)
        self.sync = sync
        self.advertised_service = advertised_service

    @dbus_property(access=PropertyAccess.READ)
    def Type(self) -> "s":
        return "peripheral"

    @dbus_property(access=PropertyAccess.READ)
    def ServiceUUIDs(self) -> "as":
        return [self.advertised_service]

    @dbus_property(access=PropertyAccess.READ)
    def LocalName(self) -> "s":
        return "PiAgent"

    @method()
    def Release(self):
        self.sync.invalidate_session()
        self.sync.bluez_gone.set()


async def serve(peer: str, enrollment_state: Path | None = None) -> None:
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    try:
        [owner] = await call(bus, DBUS, DBUS_PATH, DBUS, "GetNameOwner", "s", [BLUEZ])
        [objects] = await call(bus, owner, "/", MANAGER_IFACE, "GetManagedObjects")
        adapters = [
            (path, interfaces["org.bluez.Adapter1"])
            for path, interfaces in objects.items()
            if {
                "org.bluez.Adapter1", "org.bluez.GattManager1", "org.bluez.LEAdvertisingManager1",
            }.issubset(interfaces) and interfaces["org.bluez.Adapter1"]["Powered"].value
        ]
        if not adapters:
            raise RuntimeError("No powered Bluetooth LE advertising adapter is available")
        adapter, adapter_properties = min(adapters, key=lambda entry: entry[0])
        digest = hashlib.blake2s(adapter_properties["Address"].value.encode(), digest_size=4)
        identity = ("PiAgent/" + digest.hexdigest()).encode("ascii")
        enrollment = None
        advertised_service = SERVICE_UUID
        if enrollment_state is not None:
            from raspberry.enrollment.authority import Authority
            from raspberry.enrollment.gatt import Enrollment, EnrollmentCharacteristic, EnrollmentService
            from raspberry.enrollment.protocol import CHALLENGE, INFO, REQUEST as ENROLLMENT_REQUEST, RESULT as ENROLLMENT_RESULT, SERVICE

            enrollment = Enrollment(Authority(enrollment_state), adapter, ENROLLMENT_PATH)
            bus.export(ENROLLMENT_PATH, EnrollmentService())
            for number, uuid in enumerate((INFO, CHALLENGE, ENROLLMENT_REQUEST, ENROLLMENT_RESULT)):
                bus.export(f"{ENROLLMENT_PATH}/characteristic{number}", EnrollmentCharacteristic(enrollment, uuid))
            advertised_service = SERVICE
        sync = TimeSync(bus, owner, adapter, peer, enrollment)
        bus.add_message_handler(sync.handle_message)
        for rule in (
            "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',"
            "member='NameOwnerChanged',arg0='org.bluez'",
            f"type='signal',sender='{owner}',interface='{PROPERTIES_IFACE}',"
            f"member='PropertiesChanged',arg0='{DEVICE_IFACE}'",
            f"type='signal',sender='{owner}',interface='{MANAGER_IFACE}',member='InterfacesRemoved'",
        ):
            await call(bus, DBUS, DBUS_PATH, DBUS, "AddMatch", "s", [rule])
        bus.export(SERVICE_PATH, TimeService())
        for number, uuid in enumerate((DEVICE_UUID, REQUEST_UUID, RESPONSE_UUID, RESULT_UUID, STATUS_UUID)):
            bus.export(f"{SERVICE_PATH}/characteristic{number}", TimeCharacteristic(sync, uuid, identity))
        bus.export(ADVERT_PATH, Advertisement(sync, advertised_service))
        await call(bus, owner, adapter, "org.bluez.GattManager1", "RegisterApplication", "oa{sv}", [APP_PATH, {}])
        await call(bus, owner, adapter, "org.bluez.LEAdvertisingManager1", "RegisterAdvertisement", "oa{sv}", [ADVERT_PATH, {}])
        LOG.info("Advertising PiAgent on %s, permanent enrollment=%s", adapter, enrollment is not None)
        async with asyncio.TaskGroup() as tasks:
            disconnected = tasks.create_task(bus.wait_for_disconnect())
            bluez_stopped = tasks.create_task(sync.bluez_gone.wait())
            _, waiting = await asyncio.wait((disconnected, bluez_stopped), return_when=asyncio.FIRST_COMPLETED)
            for task in waiting:
                task.cancel()
        raise RuntimeError("D-Bus or the BlueZ time-sync registration disconnected")
    finally:
        bus.disconnect()


def main() -> None:
    parser = argparse.ArgumentParser(description="PiAgent BLE time-sync GATT server")
    parser.add_argument("--peer-file", type=Path)
    parser.add_argument("--enrollment-state", type=Path)
    args = parser.parse_args()
    if (args.peer_file is None) == (args.enrollment_state is None):
        parser.error("Specify either a trusted peer file or a permanent enrollment state directory")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    try:
        peer = args.peer_file.read_text(encoding="ascii").strip().upper() if args.peer_file else ""
        if peer and not re.fullmatch(r"(?:[0-9A-F]{2}:){5}[0-9A-F]{2}", peer):
            raise ValueError("Peer file must contain one bonded Bluetooth identity address")
        asyncio.run(serve(peer, args.enrollment_state))
    except (OSError, ValueError, DBusError, TimeoutError, RuntimeError) as exc:
        LOG.error("BLE time-sync service stopped: %s", exc)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
