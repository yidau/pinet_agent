"""Clock adjustment endpoint reachable only by the local BLE service account."""

import logging
import os
import socket
import struct
import time
from collections.abc import Callable

from .protocol import (
    CONFIRM_BACKWARD,
    FAILED,
    HELPER_REQUEST,
    HELPER_RESULT,
    MAX_PHONE_MS,
    MIN_PHONE_MS,
    OK,
    REJECTED,
    SESSION_MS,
    mono_ms,
    validate_sample,
)

LOG = logging.getLogger("piagent.clock")
PEER_CREDENTIALS = struct.Struct("3i")
NANOSECONDS_PER_MS = 1_000_000
CLOCK_JUMP_MS = 100
READBACK_TOLERANCE_MS = 250


def set_realtime_ns(value: int) -> None:
    time.clock_settime_ns(time.CLOCK_REALTIME, value)


class ClockAdjuster:
    def __init__(
        self,
        read_wall_ns: Callable[[], int] = time.time_ns,
        read_mono_ms: Callable[[], int] = mono_ms,
        set_wall_ns: Callable[[int], None] = set_realtime_ns,
    ) -> None:
        self.read_wall_ns = read_wall_ns
        self.read_mono_ms = read_mono_ms
        self.set_wall_ns = set_wall_ns
        self.last_step_mono_ms = -1

    def adjust(self, packet: bytes) -> tuple[int, int]:
        try:
            confirmed, t1, t2, t3, t4, mono_t2, mono_t3 = HELPER_REQUEST.unpack(packet)
            if confirmed not in (0, 1):
                raise ValueError("Invalid confirmation flag")
            offset, delay = validate_sample(t1, t2, t3, t4)
            started = self.read_mono_ms()
            if (
                not 0 <= mono_t2 <= mono_t3 <= started
                or mono_t2 <= self.last_step_mono_ms
                or started - mono_t2 > SESSION_MS
                or abs((t3 - t2) - (mono_t3 - mono_t2)) > CLOCK_JUMP_MS
            ):
                raise ValueError("Invalid, replayed, or stale sample")
            current_ns = self.read_wall_ns()
            current_ms = current_ns // NANOSECONDS_PER_MS
            if abs((current_ms - t3) - (started - mono_t3)) > CLOCK_JUMP_MS:
                raise ValueError("System clock changed after sampling")
            target_ns = current_ns - offset * NANOSECONDS_PER_MS
            if not MIN_PHONE_MS <= target_ns // NANOSECONDS_PER_MS < MAX_PHONE_MS:
                raise ValueError("Target UTC time is outside the accepted range")
        except (ValueError, struct.error) as error:
            LOG.info("Clock request rejected: %s", error)
            return REJECTED, 0

        if offset > 0 and not confirmed:
            return CONFIRM_BACKWARD, 0
        try:
            if offset:
                self.set_wall_ns(target_ns)
            self.last_step_mono_ms = self.read_mono_ms()
            readback_ms = self.read_wall_ns() // NANOSECONDS_PER_MS
        except OSError as error:
            LOG.warning("Clock update failed: %s", error)
            return FAILED, 0

        elapsed_ms = self.last_step_mono_ms - started
        target_ms = target_ns // NANOSECONDS_PER_MS
        if abs(readback_ms - target_ms - elapsed_ms) > READBACK_TOLERANCE_MS:
            LOG.warning("Clock readback differed from the target")
            return FAILED, 0
        LOG.info("Clock synchronized: offset_ms=%d rtt_ms=%d elapsed_ms=%d", offset, delay, elapsed_ms)
        return OK, readback_ms


def handle_connection(channel: socket.socket, allowed_uid: int, adjuster: ClockAdjuster) -> None:
    channel.settimeout(2)
    credentials = channel.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, PEER_CREDENTIALS.size)
    _pid, uid, _gid = PEER_CREDENTIALS.unpack(credentials)
    if uid != allowed_uid:
        return
    packet = bytearray()
    while len(packet) <= HELPER_REQUEST.size:
        part = channel.recv(HELPER_REQUEST.size + 1 - len(packet))
        if not part:
            break
        packet.extend(part)
    channel.sendall(HELPER_RESULT.pack(*adjuster.adjust(bytes(packet))))


def main() -> None:
    import pwd

    logging.basicConfig(level=logging.INFO)
    if os.environ.get("LISTEN_PID") != str(os.getpid()) or os.environ.get("LISTEN_FDS") != "1":
        raise SystemExit("Run this service through piagent-clock.socket")
    allowed_uid = pwd.getpwnam("piagent-ble").pw_uid
    adjuster = ClockAdjuster()
    with socket.socket(fileno=3) as listener:
        while True:
            channel, _address = listener.accept()
            with channel:
                try:
                    handle_connection(channel, allowed_uid, adjuster)
                except OSError as error:
                    LOG.info("Clock IPC ended: %s", error)


if __name__ == "__main__":
    main()
