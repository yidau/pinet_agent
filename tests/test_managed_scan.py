"""C1/C2 software tests with mock nl80211 attributes and Kismet transport."""

import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
from urllib.parse import parse_qs

from raspberry.mcp_server.kismet_adapter import KismetAdapter, KismetError
from raspberry.mcp_server.managed_scan import access_point, empty_state, kismet_reports, read_managed_scan


class ManagedScanFormatTests(unittest.TestCase):
    def point(self, fields):
        attrs = {"NL80211_BSS_BSSID": "02:00:00:00:00:01",
                 "NL80211_BSS_CAPABILITY": {"VALUE": 17},
                 "NL80211_BSS_SEEN_MS_AGO": 2000, "NL80211_BSS_FREQUENCY": 2412,
                 "NL80211_BSS_SIGNAL_MBM": {"VALUE": -5750},
                 "NL80211_BSS_INFORMATION_ELEMENTS": {"SSID": b"lab", "RSN": {
                     "auth_suites": ["PSK"], "pairwise_cipher": ["CCMP"]}}, **fields}
        bss = Mock()
        bss.get_attr.side_effect = attrs.get
        return access_point(bss, now=1700001000, scan_seconds=3)

    def test_c2_structured_radio_observations(self):
        ap = self.point({})
        report, = kismet_reports([ap])
        self.assertEqual(report, {"timestamp": 1700000998, "bssid": "02:00:00:00:00:01",
                                  "ssid": "lab", "capabilities": "[RSN-PSK-CCMP][ESS]",
                                  "channel": "1", "freqkhz": 2412000, "signal": -57.5})
        hidden = self.point({"NL80211_BSS_INFORMATION_ELEMENTS": {"SSID": b"\x00"},
                             "NL80211_BSS_CAPABILITY": {"VALUE": 1}, "NL80211_BSS_SIGNAL_MBM": None})
        report, = kismet_reports([hidden])
        self.assertIsNone(hidden["name"])
        self.assertNotIn("ssid", report)
        self.assertNotIn("signal", report)
        self.assertEqual(report["capabilities"], "[ESS]")
        unlabelled = self.point({"NL80211_BSS_INFORMATION_ELEMENTS": {
            "VENDOR": [b"\x00\x50\xf2\x01"], "SSID": b""}})
        wpa, = kismet_reports([unlabelled])
        self.assertEqual(wpa["capabilities"], "[WPA-UNKNOWN][ESS]")
        self.assertNotIn("ssid", wpa)
        unknown_security = self.point({"NL80211_BSS_INFORMATION_ELEMENTS": {}})
        self.assertIsNone(unknown_security["security"])
        self.assertEqual(kismet_reports([unknown_security]), [])
        self.assertIsNone(self.point({"NL80211_BSS_SEEN_MS_AGO": 100000}))
        self.assertIsNone(self.point({"NL80211_BSS_CAPABILITY": {"VALUE": 2}}))

    def test_c3_held_interrupted_and_expired_scan_states(self):
        now = time.monotonic()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "status.json"
            self.assertEqual(read_managed_scan(path)["status"], "DEGRADED")
            hold = empty_state("Scan suspended by operator.")
            def read(result, age):
                path.write_text(json.dumps({**result, "written_monotonic": now - age}))
                return read_managed_scan(path)
            self.assertEqual(read(hold, 600)["reason"], hold["reason"])
            interrupted = read({**hold, "in_progress": True}, 60)
            self.assertFalse(interrupted["in_progress"])
            self.assertEqual(interrupted["status"], "DEGRADED")
            confirmed = {**hold, "status": "AVAILABLE", "source_uuid": "9af16f76-b038-43ca-8adc-88a8abb581e4"}
            self.assertEqual(read(confirmed, 301)["status"], "DEGRADED")
            self.assertEqual(read(confirmed, 2)["status"], "AVAILABLE")
            self.assertEqual(read({**confirmed, "access_points": [{}]}, 2)["status"], "ERROR")

    def test_c1_scanreport_acknowledges_real_and_empty_batches(self):
        adapter = KismetAdapter("http://127.0.0.1:2810", "test-scanreport")
        uid = "9af16f76-b038-43ca-8adc-88a8abb581e4"
        with patch("raspberry.mcp_server.kismet_adapter.http.client.HTTPConnection") as http:
            con = http.return_value
            reply = con.getresponse.return_value
            reply.status = 200
            reply.read.return_value = b'{"success": true}'
            for reports in [kismet_reports([self.point({})]), []]:
                adapter.submit_scan_report(uid, "lab radio", reports)
                method, path, body, headers = con.request.call_args.args
                self.assertEqual((method, path), ("POST", "/phy/phy80211/scan/scan_report.cmd"))
                self.assertEqual(headers["Cookie"], "KISMET=test-scanreport")
                payload = json.loads(parse_qs(body)["json"][0])
                self.assertEqual(payload, {"source_uuid": uid, "source_name": "lab radio", "reports": reports})
            reply.read.return_value = b'{"success": false}'
            with self.assertRaises(KismetError):
                adapter.submit_scan_report(uid, "lab radio", [])
