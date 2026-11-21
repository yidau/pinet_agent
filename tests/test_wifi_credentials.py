"""Offline checks for V0.3 W1–W3, D1 and D4 using a hostapd model."""

import json
import unittest

from raspberry.enrollment.wifi_helper import WifiCredentials, WifiError, parse_request


FIRST_ID = "1" * 32
SECOND_ID = "2" * 32
FIRST_KEY = "first-device-test-key"
SECOND_KEY = "second-device-test-key"


class MemoryPskFile:
    def __init__(self):
        self.entries = {}

    def read(self):
        return self.entries.copy()

    def replace(self, entries):
        self.entries = entries.copy()


class SimulatedHostapd:
    def __init__(self, store):
        self.store = store
        self.active_keys = set()
        self.connections = {}
        self.online = True

    def check_config(self):
        if not self.online:
            raise OSError("Hostapd connection unavailable")

    def reload_psks(self):
        self.active_keys = set(self.store.entries.values())
        for address, key in list(self.connections.items()):
            if key not in self.active_keys:
                del self.connections[address]

    def connect(self, address, key):
        if key not in self.active_keys:
            return False
        self.connections[address] = key
        return True


class WifiCredentialTests(unittest.TestCase):
    def setUp(self):
        self.store = MemoryPskFile()
        self.hostapd = SimulatedHostapd(self.store)
        self.manager = WifiCredentials(self.store, self.hostapd)

    def update(self, **fields):
        self.manager.update(*parse_request(json.dumps(fields).encode("ascii")))

    def test_w1_w2_independent_keys_with_changed_private_mac(self):
        self.update(op="set", credential_id=FIRST_ID, psk=FIRST_KEY)
        self.update(op="set", credential_id=SECOND_ID, psk=SECOND_KEY)
        self.assertTrue(self.hostapd.connect("02:00:00:00:00:01", FIRST_KEY))
        self.assertTrue(self.hostapd.connect("02:00:00:00:00:02", SECOND_KEY))
        self.assertTrue(self.hostapd.connect("02:00:00:00:00:03", FIRST_KEY))
        self.assertFalse(self.hostapd.connect("02:00:00:00:00:04", "unregistered"))
        with self.assertRaises(WifiError):
            self.update(op="set", credential_id="3" * 32, psk=FIRST_KEY)

    def test_w3_d1_d4_revocation_is_persistent_and_selective(self):
        self.update(op="set", credential_id=FIRST_ID, psk=FIRST_KEY)
        self.update(op="set", credential_id=SECOND_ID, psk=SECOND_KEY)
        first = "02:00:00:00:00:01"
        second = "02:00:00:00:00:02"
        self.assertTrue(self.hostapd.connect(first, FIRST_KEY))
        self.assertTrue(self.hostapd.connect(second, SECOND_KEY))

        self.hostapd.online = False
        with self.assertRaises(OSError):
            self.update(op="revoke", credential_id=FIRST_ID)
        self.assertNotIn(FIRST_KEY, self.store.entries.values())
        self.assertTrue(self.manager.reload_pending)

        self.hostapd.online = True
        self.manager.synchronize()
        self.assertNotIn(first, self.hostapd.connections)
        self.assertFalse(self.hostapd.connect(first, FIRST_KEY))
        self.assertEqual(self.hostapd.connections[second], SECOND_KEY)


if __name__ == "__main__":
    unittest.main()
