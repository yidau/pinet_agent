"""PiAgent BLE time-sync wire constants and bounded four-timestamp calculation."""

import struct
import time

VERSION = 1
SERVICE_UUID = "2f70e150-8c6b-4ee4-8f11-25d94aa85c00"
DEVICE_UUID = SERVICE_UUID[:-2] + "01"
REQUEST_UUID = SERVICE_UUID[:-2] + "02"
RESPONSE_UUID = SERVICE_UUID[:-2] + "03"
RESULT_UUID = SERVICE_UUID[:-2] + "04"
STATUS_UUID = SERVICE_UUID[:-2] + "05"

STATUS = struct.Struct(">BBQ")
REQUEST = struct.Struct(">BQHq")
RESPONSE = struct.Struct(">Hqq")
RESULT = struct.Struct(">QHBq")

PROBE, APPLY, APPLY_BACKWARD = 1, 2, 3
OK, REJECTED, FAILED, CONFIRM_BACKWARD, NO_RESULT, PENDING = range(6)

HELPER_REQUEST = struct.Struct(">Bqqqqqq")
HELPER_RESULT = struct.Struct(">Bq")
SESSION_MS = 60_000
MAX_DELAY_MS = 750
MAX_ELAPSED_MS = 5_000
MAX_ADJUST_MS = 5 * 366 * 24 * 60 * 60 * 1_000
MIN_PHONE_MS = 1_704_067_200_000  # 2024-01-01T00:00:00Z
MAX_PHONE_MS = 4_102_444_800_000  # 2100-01-01T00:00:00Z


def now_ms() -> int:
    return time.time_ns() // 1_000_000


def mono_ms() -> int:
    return time.monotonic_ns() // 1_000_000


def validate_sample(t1: int, t2: int, t3: int, t4: int) -> tuple[int, int]:
    if not MIN_PHONE_MS <= t1 <= t4 < MAX_PHONE_MS:
        raise ValueError("Phone UTC time is outside the accepted range")
    phone_elapsed, pi_elapsed = t4 - t1, t3 - t2
    if not 0 <= pi_elapsed <= MAX_ELAPSED_MS or phone_elapsed > MAX_ELAPSED_MS:
        raise ValueError("Invalid elapsed time")
    delay = phone_elapsed - pi_elapsed
    if not 0 <= delay <= MAX_DELAY_MS:
        raise ValueError("Round-trip delay is outside the accepted range")
    twice_offset = (t2 - t1) + (t3 - t4)
    if abs(twice_offset) > 2 * MAX_ADJUST_MS:
        raise ValueError("Clock adjustment is too large")
    offset = abs(twice_offset) // 2
    return (-offset if twice_offset < 0 else offset), delay
