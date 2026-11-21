"""Deterministic checks within the V0.2 time synchronization test group."""

import unittest

from raspberry.time_sync.clock_helper import ClockAdjuster
from raspberry.time_sync.protocol import (
    CONFIRM_BACKWARD,
    FAILED,
    HELPER_REQUEST,
    MAX_ADJUST_MS,
    OK,
    REJECTED,
    validate_sample,
)

PHONE_MS = 1_795_309_200_000
NS_PER_MS = 1_000_000


class SimulatedClock:
    def __init__(self) -> None:
        self.mono = 1_100
        self.wall_ns = 0
        self.steps = []
        self.adjuster = ClockAdjuster(lambda: self.wall_ns, lambda: self.mono, self.set_wall)

    def set_wall(self, value: int) -> None:
        self.steps.append(value)
        self.wall_ns = value

    def sample(self, offset: int, confirm: int = 0, *, phone: int = PHONE_MS) -> bytes:
        mono_t2 = self.mono - 10
        mono_t3 = mono_t2 + 4
        t2 = phone + 20 + offset
        t3 = t2 + 4
        self.wall_ns = (t3 + self.mono - mono_t3) * NS_PER_MS
        return HELPER_REQUEST.pack(confirm, phone, t2, t3, phone + 44, mono_t2, mono_t3)


class TimeSyncTests(unittest.TestCase):
    def test_t1_pi_behind(self) -> None:
        clock = SimulatedClock()
        packet = clock.sample(-3_600_000)
        self.assertEqual(validate_sample(*HELPER_REQUEST.unpack(packet)[1:5]), (-3_600_000, 40))
        self.assertEqual(clock.adjuster.adjust(packet), (OK, PHONE_MS + 30))

    def test_t2_pi_ahead_needs_confirmation(self) -> None:
        clock = SimulatedClock()
        self.assertEqual(clock.adjuster.adjust(clock.sample(3_600_000)), (CONFIRM_BACKWARD, 0))
        self.assertEqual(clock.steps, [])
        self.assertEqual(clock.adjuster.adjust(clock.sample(3_600_000, 1)), (OK, PHONE_MS + 30))

    def test_t3_new_sync_succeeds_but_replay_is_rejected(self) -> None:
        clock = SimulatedClock()
        first = clock.sample(-2_000)
        self.assertEqual(clock.adjuster.adjust(first)[0], OK)
        self.assertEqual(clock.adjuster.adjust(first), (REJECTED, 0))
        clock.mono += 100
        self.assertEqual(clock.adjuster.adjust(clock.sample(0, phone=PHONE_MS + 100))[0], OK)
        self.assertEqual(len(clock.steps), 1)

    def test_t6_malformed_out_of_range_and_stale_samples(self) -> None:
        clock = SimulatedClock()
        self.assertEqual(clock.adjuster.adjust(b"\x00"), (REJECTED, 0))
        self.assertEqual(clock.adjuster.adjust(clock.sample(-MAX_ADJUST_MS - 1)), (REJECTED, 0))
        stale = clock.sample(-10_000)
        clock.mono += 60_001
        self.assertEqual(clock.adjuster.adjust(stale), (REJECTED, 0))
        self.assertEqual(clock.steps, [])
        with self.assertRaises(ValueError):
            validate_sample(PHONE_MS, PHONE_MS, PHONE_MS + 10, PHONE_MS + 1)

    def test_t7_failed_readback_is_reported(self) -> None:
        clock = SimulatedClock()
        clock.adjuster.set_wall_ns = lambda _value: None
        self.assertEqual(clock.adjuster.adjust(clock.sample(-10_000)), (FAILED, 0))

    def test_t7_permission_failure_is_reported(self) -> None:
        clock = SimulatedClock()

        def denied(_value: int) -> None:
            raise PermissionError("clock permission denied")

        clock.adjuster.set_wall_ns = denied
        self.assertEqual(clock.adjuster.adjust(clock.sample(-10_000)), (FAILED, 0))
