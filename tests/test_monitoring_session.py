import io
from threading import Event
import time
import unittest
from unittest.mock import Mock, patch

from raspberry.mcp_server import phone_radio
from raspberry.mcp_server.managed_scan import ScanUnavailable, check_scan_radio
from raspberry.mcp_server.monitoring_session import MonitoringError, MonitoringSession, _Run, monitoring_for


BSSID = "02:00:00:00:00:01"
SECOND = "02:00:00:00:00:02"


def point(address, when, dbm, channel="1", security="WPA2"):
    return {"mac": address, "ssid": "Lab", "last_seen": when, "rssi_dbm": dbm,
            "channel": channel, "security": security}


class MonitoringTests(unittest.TestCase):
    def test_t5_t6_confirmed_bounded_lifecycle_and_single_owner(self):
        entered, release = Event(), Event()

        def pending(source, cancel, deadline):
            entered.set()
            release.wait(2)
            return {"access_points": [point(BSSID, time.time(), -50)]}

        session = MonitoringSession(lambda: "managed_scan", pending)
        self.addCleanup(session.close)
        for kwargs in ({"confirm": False}, {"confirm": True, "duration_seconds": 3601},
                       {"confirm": True, "interval_seconds": -1}, {"confirm": True, "interval_seconds": "30"}):
            with self.assertRaises(MonitoringError):
                session.start(**kwargs)
        started = session.start(True)
        self.assertEqual((started["interval_seconds"], started["duration_seconds"]), (30, 600))
        self.assertEqual(started["state"], "running")
        self.assertTrue(entered.wait(1))
        self.assertEqual(session.stop(True)["state"], "stopping")
        with self.assertRaises(MonitoringError) as duplicate:
            session.start(True)
        self.assertEqual(duplicate.exception.code, "MONITORING_CONFLICT")
        release.set()
        session.close()
        stopped = session.stop(True)
        self.assertEqual((stopped["state"], stopped["scan_count"]), ("stopped", 0))

    def test_t5_t8_managed_job_counts_only_its_new_result_and_expires(self):
        calls = []
        previous, mine = "a" * 32, "b" * 32
        report = {"scan_mode": "monitoring", "scan_id": previous, "status": "AVAILABLE",
                  "truncated": False, "access_points": []}
        fresh = {**report, "scan_id": mine, "access_points": [point(BSSID, time.time(), -50)]}
        reader = Mock(side_effect=[report, fresh])
        manager = monitoring_for(Mock(get_datasources=Mock(return_value=[])), reader)
        self.addCleanup(manager.close)

        def broker(action):
            calls.append(action)
            return mine if action == "session-scan" else None

        with patch("raspberry.mcp_server.monitoring_session.session_radio", side_effect=broker):
            manager.start(True, duration_seconds=1)
            manager._worker.join(2)
        status = manager.status()
        self.assertEqual(calls, ["session-check", "session-scan"])
        self.assertEqual((status["state"], status["scan_count"], status["ap_count"]), ("completed", 1, 1))
        self.assertEqual(status["summary"]["baseline_ap_count"], 1)
        self.assertEqual(status["new_ap_count"], 0)
        self.assertEqual(manager.history(BSSID)["history"][0]["samples"][0]["observation_source"], "managed_scan")

    def test_t6_stop_cancels_the_dedicated_inflight_job(self):
        acknowledged = Event()
        actions = []
        mine = "b" * 32

        def broker(action, invocation=None):
            actions.append((action, invocation))
            if action == "session-scan":
                acknowledged.set()
                return mine

        manager = monitoring_for(Mock(get_datasources=Mock(return_value=[])), lambda: {})
        with patch("raspberry.mcp_server.monitoring_session.session_radio", side_effect=broker):
            manager.start(True)
            try:
                self.assertTrue(acknowledged.wait(1))
                manager.stop(True)
            finally:
                manager.close()
        self.assertEqual(actions, [("session-check", None), ("session-scan", None), ("session-stop", mine)])
        self.assertEqual((manager.status()["state"], manager.status()["scan_count"]), ("stopped", 0))

    def test_t5_t6_broker_rejects_orphan_or_queued_run_and_never_stops_another_invocation(self):
        previous, mine = "a" * 32, "b" * 32
        idle = {"ActiveState": "inactive", "Job": "", "InvocationID": previous}
        for unit in ({**idle, "Job": "123"}, {**idle, "ActiveState": "activating"}):
            with patch.object(phone_radio, "_session_unit", return_value=unit), patch.object(phone_radio, "_systemctl") as cmd:
                self.assertEqual(phone_radio._session_job(None), b"BUSY\n")
                self.assertEqual(phone_radio._session_job(mine), b"OK\n")
                if unit["ActiveState"] == "inactive":
                    self.assertEqual(phone_radio._session_job(previous), b"OK\n")
                cmd.assert_not_called()
        with patch.object(phone_radio, "_session_unit", side_effect=[idle, {**idle, "InvocationID": mine}]), \
                patch.object(phone_radio, "_systemctl", return_value=Mock(returncode=0)) as cmd:
            self.assertEqual(phone_radio._session_job(None), f"OK {mine}\n".encode("ascii"))
            cmd.assert_called_once_with("--no-block", "start", phone_radio.SESSION_WIFI, timeout=1)

    def test_t7_t8_per_ap_evidence_and_changes_are_source_timed(self):
        run = _Run("monitor_mode", 30, 600, started=100)
        run.record({"access_points": [point(SECOND, 80, -20), point(BSSID, 100, -53)]})
        run.record({"access_points": [point(BSSID, 100, -53)]})
        run.record({"access_points": [point(BSSID, 130, -52), point(SECOND, 130, -61)]})
        run.record({"access_points": [{**point(BSSID, 160, -52, "11", "WPA3"), "rssi_observed_at": 130}]})
        manager = MonitoringSession(None, None)
        manager._run = run
        summary = manager.status()["summary"]
        self.assertEqual((summary["baseline_ap_count"], summary["new_ap_count"]), (1, 1))
        self.assertEqual((summary["channel_change_count"], summary["security_change_count"]), (1, 1))
        events = manager.events()["events"]
        self.assertEqual([e["type"] for e in events], ["new_ap", "channel_change", "security_change"])
        self.assertEqual(len({e["id"] for e in events}), 3)
        samples = manager.history(BSSID)["history"][0]["samples"]
        self.assertEqual([(s["timestamp"], s["rssi_dbm"]) for s in samples], [(100, -53), (130, -52), (160, None)])
        self.assertEqual({s["observation_source"] for s in samples}, {"monitor_mode"})
        self.assertEqual(manager.access_point(SECOND)["last_seen"], 130)
        for index in range(70):
            when = 190 + 30 * index
            channel, security = ("1", "WPA2") if index % 2 == 0 else ("11", "WPA3")
            run.record({"access_points": [point(BSSID, when, -53, channel, security)]})
        all_events = manager.events()
        self.assertEqual(len(all_events["events"]), 128)
        self.assertTrue(all_events["truncated"])
        ap_events = manager.evidence(BSSID)["events"]
        self.assertEqual(len(ap_events["events"]), 142)
        self.assertEqual(ap_events["total"], 142)
        self.assertFalse(ap_events["truncated"])

    def test_t11_unknown_or_shared_radio_degrades_without_triggering_a_scan(self):
        def interface(index, kind, phy):
            row = Mock()
            row.get_attr.side_effect = {"NL80211_ATTR_IFINDEX": index, "NL80211_ATTR_IFTYPE": kind,
                                        "NL80211_ATTR_WIPHY": phy}.get
            return row

        station = interface(1, 2, 0)
        for rows in ([], [station, interface(2, 0, 0)], [station, interface(2, 99, 0)],
                     [station, interface(2, 3, -1)], [station, interface(2, 3, None)],
                     [station, interface(2, 9, 0)]):
            with self.assertRaises(ScanUnavailable):
                check_scan_radio(rows, 1, False, True)
        check_scan_radio([station, interface(2, 3, 1)], 1, False, True)
        for phys, expected in ((["phy0", "phy0"], b"SHARED\n"), (OSError(), b"FAILED\n")):
            with self.subTest(expected=expected), patch.object(phone_radio, "_interface_phy", side_effect=phys), \
                    patch.object(phone_radio, "_systemctl") as systemctl:
                out = io.BytesIO()
                phone_radio._serve_one(io.BytesIO(b"session-scan\n"), out)
                self.assertEqual(out.getvalue(), expected)
                systemctl.assert_not_called()
        adapter = Mock(get_datasources=Mock(return_value=[]))
        manager = monitoring_for(adapter, Mock())
        with patch.object(phone_radio, "_broker_request", return_value=b"SHARED\n") as request:
            state, reason = manager.availability([])
            self.assertEqual(state, "DEGRADED")
            self.assertIn("共用", reason)
            with self.assertRaises(MonitoringError):
                manager.start(True)
            self.assertTrue(all(call.args == ("session-check",) for call in request.call_args_list))
            self.assertEqual(manager.availability([{"driver": "linuxwifi", "running": True,
                                                   "paused": False, "error": False}])[0], "AVAILABLE")
