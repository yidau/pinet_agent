"""T10: what the Agent can actually read from the WirelessService API."""

import unittest
from unittest.mock import Mock

from raspberry.mcp_server.managed_scan import empty_state
from raspberry.mcp_server.wireless_service import WirelessError, WirelessService


class InvestigationTests(unittest.TestCase):
    def test_t10_exact_attribution_and_stable_pages_including_retained_subject(self):
        address = "02:00:00:00:00:01"
        neighbor = "02:00:00:00:00:02"
        adapter = Mock()
        source = {"driver": "linuxwifi", "uuid": "monitor", "running": True, "paused": False, "error": False}
        adapter.get_datasources.return_value = [source]
        ap = {"id": "ap-key", "mac": address, "ssid": "Office", "name": "Office", "type": "Wi-Fi AP",
              "phy": "IEEE802.11", "last_seen": 100, "channel": "1", "rssi_dbm": -52,
              "samples": [{"timestamp": i, "rssi_dbm": -50} for i in range(75, 99)]}
        adjacent = {**ap, "id": "elsewhere", "mac": neighbor}
        adapter.get_source_devices.return_value = ([ap, adjacent], 2)
        linked = {"timestamp": 91, "message": "Observed channel change", "device_id": "ap-key",
                  "type": "CHANNELCHANGE", "phy_id": 3}
        unrelated = {**linked, "timestamp": 90, "device_id": "elsewhere", "device_macs": [neighbor]}
        adapter.get_alerts.return_value = [{**linked, "timestamp": i} for i in range(80, 125)] + [unrelated]
        adapter.get_wifi_phy_id.return_value = 3
        monitor = Mock()
        session_ap = {**ap, "bssid": address, "observation_source": "managed_scan",
                      "observation_sources": ["managed_scan"], "kismet_device_ids": ["ap-key"]}
        monitor.evidence.return_value = {
            "access_point": session_ap, "events": {"events": [], "total": 0, "truncated": False},
            "history": {"history": [{"samples": [{"timestamp": 89, "rssi_dbm": -57, "channel": "6",
                        "security": "WPA2", "observation_source": "managed_scan"}]}], "truncated": False},
        }
        wifi = WirelessService(adapter, scan_reader=lambda: empty_state("No current scan."), monitoring=monitor)
        first = wifi.call("get_wireless_investigation", ap_id=address)
        all_rows = list(first["evidence"])
        self.assertEqual(len(all_rows), 12)
        self.assertTrue(first["limitations"])
        self.assertEqual(first["activity_summary"]["event_count"], 45)
        summary = wifi.call("get_ap_details", ap_id=address)
        self.assertEqual(len(summary["related_events"]), 32)
        self.assertTrue(summary["related_events_truncated"])
        self.assertEqual(summary["activity_summary"]["event_count"], 45)
        # Later pages must still refer to the first snapshot, even after both sources change.
        adapter.get_datasources.return_value = []
        adapter.get_alerts.return_value = []
        page = first
        while page["next_offset"] is not None:
            page = wifi.call("get_wireless_investigation", ap_id=address, snapshot_id=first["snapshot_id"],
                             offset=page["next_offset"])
            all_rows.extend(page["evidence"])
        self.assertEqual(len(all_rows), first["total"])
        self.assertEqual(len({record["id"] for record in all_rows}), len(all_rows))
        self.assertEqual({row["source"] for row in all_rows}, {"monitor_mode", "managed_scan", "kismet"})
        events = [row for row in all_rows if row["kind"] == "event"]
        self.assertEqual([e["timestamp"] for e in events], list(range(80, 125)))
        self.assertEqual({e["data"]["device_id"] for e in events}, {"ap-key"})
        concern = first["report"]["possible_concerns"][0]
        self.assertEqual(concern["evidence_count"], 45)
        self.assertEqual(concern["evidence_ids"], [e["id"] for e in events[-4:]])
        with self.assertRaises(WirelessError):
            wifi.call("get_wireless_investigation", ap_id=neighbor, snapshot_id=first["snapshot_id"], offset=0)
        retained = wifi.call("get_wireless_investigation", ap_id=address)
        self.assertEqual(retained["access_point"]["bssid"], address)
        self.assertEqual(retained["activity_summary"]["observation_count"], 1)
        self.assertTrue(any("当前无线列表" in note for note in retained["limitations"]))
