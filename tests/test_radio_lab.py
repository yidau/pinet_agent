"""Radio-lab authorization and safety checks; no hardware or RF emission."""
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch
from contextlib import nullcontext

from raspberry.active_lab import daemon as lab


class LabAuthorizationTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.profiles = self.root / "profiles.json"
        self.paused = self.root / "monitor-paused"
        self.config = {
            "schema": 1,
            "profiles": [{
                "id": "isolated-lab", "enabled": True, "rf_isolated": True,
                "ssid": "PocketNet-Lab", "bssid": "02:11:22:33:44:55",
                "simulated_bssid": "02:aa:bb:cc:dd:ee", "channel": 6,
                "allowed_tests": ["probe", "ssid_lab"],
            }],
        }
        self.profiles.write_text(json.dumps(self.config))
        patcher = patch.multiple(lab, PROFILES=self.profiles, PAUSE_MARKER=self.paused)
        patcher.start()
        self.addCleanup(patcher.stop)

    def observed(self, *, bssid="02:11:22:33:44:55", channel="6", age=0):
        return {
            "bssid": bssid,
            "ssid": "PocketNet-Lab",
            "channel": channel,
            "last_seen_ms": int(time.time() * 1000) - age,
        }

    def test_matching_local_profile(self):
        result = lab.profile_for("", "02:11:22:33:44:55", "PocketNet-Lab", "6")
        self.assertEqual(result["id"], "isolated-lab")
        self.assertEqual(result["simulated_bssid"], "02:aa:bb:cc:dd:ee")

    def test_unknown_or_modified_target_refused(self):
        self.assertIsNone(lab.profile_for("isolated-lab", "02:99:22:33:44:55", "PocketNet-Lab", "6"))
        self.assertIsNone(lab.profile_for("isolated-lab", "02:11:22:33:44:55", "Other", "6"))
        self.assertIsNone(lab.profile_for("isolated-lab", "02:11:22:33:44:55", "PocketNet-Lab", "11"))

    def test_not_authorized_unless_admin_enables_rf_isolation(self):
        self.config["profiles"][0]["rf_isolated"] = False
        self.profiles.write_text(json.dumps(self.config))
        self.assertIsNone(lab.profile_for("", "02:11:22:33:44:55", "PocketNet-Lab", "6"))
        self.config["profiles"][0]["rf_isolated"] = True
        self.config["profiles"][0]["enabled"] = False
        self.profiles.write_text(json.dumps(self.config))
        self.assertIsNone(lab.profile_for("", "02:11:22:33:44:55", "PocketNet-Lab", "6"))

    def test_observation_must_be_fresh(self):
        self.assertTrue(lab.valid_observation(self.observed()))
        self.assertFalse(lab.valid_observation(self.observed(age=61000)))
        self.assertFalse(lab.valid_observation(self.observed(bssid="bad")))
        self.assertFalse(lab.valid_observation(self.observed(channel="149")))
        self.assertFalse(lab.valid_observation(self.observed(age=-5000)))

    def test_unregistered_attack_mode_denied(self):
        with patch.object(lab, "kismet_operation", return_value=nullcontext()):
            session = lab.Lab()
        result = session.request({
            "action": "check", "phone_id": "enrolled", "profile_id": "",
            "kind": "deauth", "observed": self.observed(),
        })
        self.assertFalse(result["accepted"])
        self.assertEqual(result["reason"], "not_authorized_lab_target")
        self.assertIsNone(session.proc)

    def test_registered_check_never_spawns_mdk4(self):
        with patch.object(lab, "kismet_operation", return_value=nullcontext()):
            session = lab.Lab()
        result = session.request({
            "action": "check", "phone_id": "enrolled", "profile_id": "",
            "kind": "ssid_lab", "observed": self.observed(),
        })
        self.assertTrue(result["accepted"])
        self.assertEqual(result["phase"], "available")
        self.assertEqual(result["profile_id"], "isolated-lab")
        self.assertIsNone(session.proc)

    def test_existing_pause_blocks_check(self):
        self.paused.write_text('{"paused":true}')
        with patch.object(lab, "kismet_operation", return_value=nullcontext()):
            session = lab.Lab()
        result = session.request({
            "action": "check", "phone_id": "enrolled",
            "kind": "ssid_lab", "profile_id": "",
            "observed": self.observed(),
        })
        self.assertFalse(result["accepted"])
        self.assertEqual(result["reason"], "monitor_already_paused")


if __name__ == "__main__":
    unittest.main()
