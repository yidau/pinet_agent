import json
import tempfile
import unittest
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from unittest.mock import patch

from jsonschema import Draft202012Validator
from starlette.testclient import TestClient

from raspberry.enrollment.registry import Registry
from raspberry.mcp_server.kismet_adapter import KismetAdapter
from raspberry.mcp_server.server import create_app
from raspberry.mcp_server.wireless_service import WirelessService


class McpTests(unittest.TestCase):
    def test_kismet_ap_view_uses_beacon_ssids_and_only_live_source_evidence(self):
        adapter = KismetAdapter()
        live = "99f1201e-8dd7-447e-89c5-90dea2c83aca"
        replay = "9dac88fb-463a-4827-b927-15f3dc7cc818"
        device = {
            "kismet.device.base.macaddr": "02:00:00:00:00:01",
            "kismet.device.base.key": "first", "kismet.device.base.name": "device label",
            "kismet.device.base.type": "Wi-Fi AP", "kismet.device.base.phyname": "IEEE802.11",
            "kismet.device.base.first_time": 50, "kismet.device.base.last_time": 70,
            "kismet.device.base.frequency": 5180000,
            "kismet.device.base.related_devices": {"dot11_bssid": ["second"]},
            "kismet.device.base.seenby": [{"kismet.common.seenby.uuid": live}],
            "advertised_ssid": " Cafe ", "beacon_security": "WPA3",
        }
        cloaked = {**device, "kismet.device.base.key": "second", "ssid_hidden": 1}
        offline = {**device, "kismet.device.base.seenby": [{"kismet.common.seenby.uuid": replay}]}
        with patch.object(adapter, "_request", return_value={"recordsFiltered": 3, "data": [device, cloaked, offline]}) as read:
            rows, _ = adapter.get_monitor_access_points([live])
        self.assertEqual(read.call_args.args[0], "/devices/views/phydot11_accesspoints/devices.json")
        self.assertEqual([r["ssid"] for r in rows], [" Cafe ", None])
        self.assertEqual((rows[0]["security"], rows[0]["frequency_mhz"], rows[0]["last_seen"]), ("WPA3", 5180, 70))
        self.assertEqual(rows[0]["related_device_ids"], ["second"])

    def test_shared_token_transport_and_boundary(self):
        token = "test-token-for-local-use-only-12345"
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json, text/event-stream",
        }
        with tempfile.TemporaryDirectory() as directory:
            app = create_app(Path(directory), token, ["testserver"])
            with TestClient(app) as client:
                self.assertEqual(client.get("/operator/radio/status", headers=headers).status_code, 403)
                self.assertEqual(client.post("/mcp", json={}).status_code, 401)
                self.assertEqual(client.post("/mcp", headers={**headers, "Host": "other"}, json={}).status_code, 421)
                self.assertEqual(
                    client.post("/mcp", headers={**headers, "Origin": "https://other.example"}, json={}).status_code,
                    403,
                )
                result = client.post("/mcp", headers=headers, json={
                    "jsonrpc": "2.0", "method": "initialize", "id": 1,
                    "params": {
                        "protocolVersion": "2025-11-25", "capabilities": {},
                        "clientInfo": {"name": "integration-test", "version": "1"},
                    },
                })
                self.assertEqual(result.status_code, 200, result.text)
                self.assertEqual(result.json()["result"]["serverInfo"]["name"], "PocketNet")


class DeviceMcpTests(unittest.TestCase):
    STATUS_FIELDS = {
        "get_system_info": {"hostname", "os", "kernel", "architecture"},
        "get_cpu_info": {"logical_cores", "used_percent", "temperature_c"},
        "get_memory_info": {"total_bytes", "available_bytes", "used_percent"},
        "get_disk_usage": {"total_bytes", "used_bytes", "free_bytes", "used_percent"},
    }
    NETWORK_DOMAINS = {
        "kismet": {
            "get_kismet_status", "get_kismet_version", "get_kismet_datasources",
            "get_kismet_devices", "get_kismet_alerts", "get_kismet_capture_status", "get_kismet_datasource_status",
        },
        "bluetooth": {"get_bluetooth_devices", "get_bluetooth_device_details"},
        "wireless_discovery": {
            "scan_wireless_environment", "get_access_points", "get_ap_details",
            "get_wireless_clients", "get_wifi_channels",
        },
        "wireless_monitoring": {
            "start_wireless_monitoring", "stop_wireless_monitoring", "get_signal_history", "get_wireless_events",
        },
        "network_discovery": {
            "get_network_profile", "get_network_interfaces", "get_arp_neighbors", "get_routes", "discover_lan_devices",
        },
        "packet_analysis": {
            "list_captures", "get_capture_metadata", "analyze_packet_capture",
            "analyze_protocol_distribution", "analyze_dns_behavior",
            "list_wireless_captures", "get_packet_statistics", "get_protocol_distribution",
            "get_capture_status", "replay_capture", "stop_capture_replay",
        },
        "security_analysis": {
            "get_security_events", "detect_rogue_ap_candidates", "detect_arp_anomalies",
            "detect_ip_conflicts", "audit_wireless_security",
            "get_wireless_security_events", "detect_ap_security_changes", "investigate_wireless_anomaly",
        },
        "network_diagnosis": {
            "diagnose_network", "investigate_network_event", "investigate_device", "generate_diagnosis_report",
        },
    }

    def setUp(self):
        # The MCP boundary uses a real HTTP client against a deterministic no-source API fixture.
        self.api = {
            ("GET", "/system/status.json"): {"kismet.system.version": "2025-09-R1"},
            ("GET", "/datasource/all_sources.json"): [],
            ("POST", "/devices/views/all/devices.json"): {"data": [], "recordsTotal": 0, "recordsFiltered": 0},
            ("GET", "/alerts/all_alerts.json"): [],
        }
        routes = self.api

        class Handler(BaseHTTPRequestHandler):
            def respond(self):
                key = self.command, self.path.split("?", 1)[0]
                if self.headers.get("Cookie") != "KISMET=test":
                    self.send_error(401)
                    return
                if key not in routes:
                    self.send_error(404)
                    return
                body = json.dumps(routes[key]).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            do_GET = do_POST = respond

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.addCleanup(server.server_close)
        worker = Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
        worker.start()
        self.addCleanup(worker.join, 1)
        self.addCleanup(server.shutdown)
        adapter = KismetAdapter(base_url=f"http://127.0.0.1:{server.server_port}", api_key="test")
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        registry = Registry(root / "devices.sqlite3")
        registry.initialize()
        token = "d" * 43
        enrollment = registry.activate(
            b"test phone public key", "test phone", register=True,
            issue_token=lambda _device: token, enable_wifi=lambda _credential: None,
        )
        self.shared_token = "s" * 32
        self.registry, self.device_id = registry, enrollment["device_id"]
        self.radio_scan = {"status": "DEGRADED", "reason": "No operator scan yet.", "source_uuid": None,
                           "access_points": [], "observed_at": None, "truncated": False}
        service = WirelessService(adapter, scan_reader=lambda: self.radio_scan)
        app = create_app(root, self.shared_token, ["testserver"], registry.database, wireless_service=service)
        self.client = self.enterContext(TestClient(app))
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json, text/event-stream",
        }

    def request(self, method, params=None, *, notification=False):
        body = {"jsonrpc": "2.0", "method": method}
        if not notification:
            body["id"] = 1
        if params is not None:
            body["params"] = params
        response = self.client.post("/mcp", headers=self.headers, json=body)
        self.assertEqual(response.status_code, 202 if notification else 200, response.text)
        return None if notification else response.json()["result"]

    def initialize(self):
        result = self.request("initialize", {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
                "clientInfo": {"name": "PocketNet AI", "version": "0.7.0"},
        })
        self.assertEqual(result["serverInfo"]["name"], "PocketNet")
        self.headers["MCP-Protocol-Version"] = result["protocolVersion"]
        self.request("notifications/initialized", notification=True)

    def call(self, name, arguments=None):
        return self.request("tools/call", {"name": name, "arguments": arguments or {}})

    def capabilities(self):
        result = self.call("get_capability_status")
        self.assertFalse(result["isError"], result)
        return {item["name"]: (item["status"], item["domain"])
                for item in result["structuredContent"]["capabilities"]}

    def test_server_discovers_catalog_and_current_capabilities(self):
        self.initialize()
        expected = {
            name: ("AVAILABLE", "device")
            for name in (*self.STATUS_FIELDS, "get_capability_status")
        }
        for domain, names in self.NETWORK_DOMAINS.items():
            expected.update({name: ("UNAVAILABLE", domain) for name in names})
        for name in self.NETWORK_DOMAINS["kismet"]:
            expected[name] = ("AVAILABLE", "kismet")
        for name in self.NETWORK_DOMAINS["wireless_discovery"]:
            expected[name] = ("DEGRADED", "wireless_discovery")
        for name in ("get_signal_history", "get_wireless_events"):
            expected[name] = ("DEGRADED", "wireless_monitoring")

        tools = self.request("tools/list")["tools"]
        self.assertCountEqual([tool["name"] for tool in tools], expected.keys())
        actual = self.capabilities()
        # Helper installation and the operator's replay directory belong to the local host.
        # Assert their domains here. C1/C6 cover their status with isolated files and helpers.
        host_dependent = {"get_bluetooth_devices", "get_bluetooth_device_details", "list_captures",
                          "get_capture_metadata", "get_capture_status", "replay_capture", "stop_capture_replay"}
        self.assertEqual(set(actual), set(expected))
        for name, (status, domain) in expected.items():
            self.assertEqual(actual[name][1], domain)
            if name not in host_dependent:
                self.assertEqual(actual[name][0], status)
        schemas = {
            "get_ap_details": {"ap_id": "string"}, "get_bluetooth_device_details": {"device_id": "string"},
            "get_capture_metadata": {"capture_id": "string"},
            "replay_capture": {"capture_id": "string", "confirm": "boolean"}, "stop_capture_replay": {"confirm": "boolean"},
        }
        for tool in tools:
            with self.subTest(tool=tool["name"]):
                self.assertTrue(tool["description"].strip())
                schema = tool["inputSchema"]
                Draft202012Validator.check_schema(schema)
                self.assertEqual(schema["type"], "object")
                params = schemas.get(tool["name"], {})
                self.assertEqual(set(schema.get("required", ())), set(params))
                self.assertEqual({k: v["type"] for k, v in schema["properties"].items()}, params)
                if tool["name"] in {"replay_capture", "stop_capture_replay"}:
                    self.assertFalse(tool["annotations"]["readOnlyHint"])
                self.assertFalse(schema["additionalProperties"])
        self.assertTrue(self.call("get_system_info", {"unexpected": 1})["isError"])

    def test_managed_report_enables_ap_queries_only_while_source_matches(self):
        self.initialize()
        ident = "532afebe-ba15-45e7-9f8f-a661019c86fc"
        self.api["GET", "/datasource/all_sources.json"] = [
            {"kismet.datasource.name": "PocketNet", "kismet.datasource.uuid": ident,
             "kismet.datasource.hardware": "IEEE80211 scan"},
        ]
        self.radio_scan.update(status="AVAILABLE", reason="", source_uuid=ident)
        summary = self.call("get_kismet_datasource_status")["structuredContent"]["source_states"]
        self.assertEqual(summary["managed_scan"]["status"], "AVAILABLE")
        self.assertEqual(summary["monitor_mode"]["status"], "DEGRADED")
        self.assertEqual(self.call("get_access_points")["structuredContent"]["access_points"], [])
        self.assertIsNone(self.call("scan_wireless_environment")["structuredContent"]["client_count"])
        self.assertTrue(self.call("get_wireless_clients")["isError"])

        mac = "02:00:00:00:00:01"
        self.radio_scan["access_points"] = [{"mac": mac, "id": mac, "name": None, "channel": "6",
                                             "security": None, "kismet_reported": False, "rssi_dbm": -56}]
        one = self.call("get_ap_details", {"ap_id": mac})["structuredContent"]["access_point"]
        self.assertEqual(one["observation_source"], "managed_scan")
        self.assertIsNone(one["ssid"])
        self.assertEqual(self.call("get_wifi_channels")["structuredContent"]["channels"],
                         [{"channel": "6", "device_count": 1}])
        self.api["GET", "/datasource/all_sources.json"] = []
        self.assertEqual(self.call("get_access_points")["structuredContent"]["status"], "degraded")

    def test_monitor_rows_are_selected_from_the_live_source(self):
        self.initialize()
        monitor_uuid = "51111234-33aa-48bb-9522-daef000000ab"
        recording_uuid = "a4001234-33aa-48bb-9522-daef000000cd"
        self.api["GET", "/datasource/all_sources.json"] = [
            {"kismet.datasource.name": driver, "kismet.datasource.uuid": ident,
             "kismet.datasource.type_driver": {"kismet.datasource.driver.type": driver},
             "kismet.datasource.running": True, "kismet.datasource.paused": False, "kismet.datasource.error": False}
            for driver, ident in (("linuxwifi", monitor_uuid), ("pcapfile", recording_uuid))
        ]
        def ap(ident):
            return {"kismet.device.base.key": ident, "kismet.device.base.type": "Wi-Fi AP",
                    "kismet.device.base.macaddr": ident, "kismet.device.base.phyname": "IEEE802.11",
                    "kismet.device.base.channel": "6"}
        live, offline = ap("02:00:00:00:00:01"), ap("02:00:00:00:00:02")
        live["kismet.device.base.seenby"] = {"1": {"kismet.common.seenby.uuid": monitor_uuid}}
        self.api["POST", "/devices/views/all/devices.json"] = {"data": [live, offline], "recordsFiltered": 2}
        view = "/devices/views/seenby-" + monitor_uuid.upper() + "/devices.json"
        self.api["POST", view] = {"data": [live], "recordsFiltered": 1}
        rows = self.call("get_access_points")["structuredContent"]["access_points"]
        self.assertEqual([(row["id"], row["observation_source"]) for row in rows],
                         [("02:00:00:00:00:01", "monitor_mode")])

    def test_ssid_groups_unique_bssids_and_keeps_per_source_observations(self):
        self.initialize()
        scan_uuid = "532afebe-ba15-45e7-9f8f-a661019c86fc"
        monitor_uuid = "51111234-33aa-48bb-9522-daef000000ab"
        self.api["GET", "/datasource/all_sources.json"] = [
            {"kismet.datasource.name": "scan report", "kismet.datasource.uuid": scan_uuid,
             "kismet.datasource.hardware": "IEEE80211 scan"},
            {"kismet.datasource.name": "monitor", "kismet.datasource.uuid": monitor_uuid,
             "kismet.datasource.type_driver": {"kismet.datasource.driver.type": "linuxwifi"},
             "kismet.datasource.running": True, "kismet.datasource.paused": False, "kismet.datasource.error": False},
        ]
        first, second, case_variant, hidden1, hidden2 = [
            f"02:ab:00:00:00:{number:02x}" for number in range(1, 6)
        ]
        started = 1770000000
        monitor = {
            "kismet.device.base.key": "monitor-key", "kismet.device.base.macaddr": first.upper(),
            "kismet.device.base.name": "Cafe", "kismet.device.base.type": "Wi-Fi AP",
            "kismet.device.base.phyname": "IEEE802.11", "kismet.device.base.channel": "6",
            "kismet.device.base.first_time": started, "kismet.device.base.last_time": started,
            "kismet.device.base.seenby": {"1": {"kismet.common.seenby.uuid": monitor_uuid,
                                                "kismet.common.seenby.last_time": started}},
            "kismet.device.base.signal": {"kismet.common.signal.type": "dbm", "kismet.common.signal.last_signal": -37},
        }
        view = f"/devices/views/seenby-{monitor_uuid.upper()}/devices.json"
        self.api["POST", view] = {"data": [monitor], "recordsFiltered": 1}

        def managed(mac, ssid, channel, signal):
            return {"id": mac, "mac": mac, "name": ssid, "channel": channel,
                    "frequency_mhz": {"1": 2412, "6": 2437, "36": 5180}[channel],
                    "security": "[RSN-PSK-CCMP][ESS]", "rssi_dbm": signal,
                    "source": "Managed Scan", "observed_at": started + 10, "kismet_reported": False}

        scan = [managed(first, "Cafe", "6", -49), managed(second, "Cafe", "36", -60),
                managed(case_variant, "cafe", "1", -55), managed(hidden1, None, "1", -70),
                managed(hidden2, "", "1", -72)]
        self.radio_scan.update(status="AVAILABLE", reason="", source_uuid=scan_uuid,
                               observed_at=started + 10, access_points=scan)
        self.call("get_access_points")
        scan[0] = dict(scan[0], observed_at=started + 20, rssi_dbm=-46, channel="11", frequency_mhz=2462)
        self.radio_scan["observed_at"] = started + 20
        data = self.call("get_access_points")["structuredContent"]
        self.assertEqual((data["network_count"], data["bssid_count"], data["channel_count"]), (4, 5, 3))
        self.assertEqual(len(data["access_points"]), 5)
        groups = data["networks"]
        self.assertCountEqual([g["bssids"] for g in groups if not g["ssid"]], [[hidden1], [hidden2]])
        self.assertEqual(next(g for g in groups if g["ssid"] == "cafe")["bssids"], [case_variant])
        cafe = next(g for g in groups if g["ssid"] == "Cafe")
        self.assertCountEqual(cafe["bssids"], [first, second])
        self.assertEqual((cafe["bssid_count"], cafe["channel_count"]), (2, 2))
        self.assertEqual((cafe["strongest_rssi_dbm"], cafe["weakest_rssi_dbm"]), (-46, -60))
        self.assertEqual(cafe["last_seen"], started + 20)

        ap = next(row for row in data["access_points"] if row["bssid"] == first)
        self.assertCountEqual(ap["observation_sources"], ["managed_scan", "monitor_mode"])
        for _ in range(2):  # Polling the same reports must not append more history.
            detail = self.call("get_ap_details", {"ap_id": ap["id"]})["structuredContent"]
            samples = [(row["timestamp"], row["rssi_dbm"], str(row["channel"]), row["observation_source"])
                       for row in detail["observations"]]
            self.assertEqual(samples, [
                (started, -37, "6", "monitor_mode"),
                (started + 10, -49, "6", "managed_scan"),
                (started + 20, -46, "11", "managed_scan"),
            ])

    def test_replay_requires_explicit_boolean_confirmation(self):
        self.initialize()
        for name, fields in (("replay_capture", {"capture_id": "sample.pcap"}), ("stop_capture_replay", {})):
            self.assertTrue(self.call(name, fields)["isError"])
            response = self.call(name, {**fields, "confirm": False})
            self.assertTrue(response["isError"])
            self.assertEqual(response["structuredContent"]["error_code"], "CONFIRMATION_REQUIRED")

    def test_existing_device_tools_return_observations(self):
        self.initialize()
        for name, fields in self.STATUS_FIELDS.items():
            with self.subTest(tool=name):
                result = self.call(name)
                self.assertFalse(result["isError"], result)
                data = result["structuredContent"]
                self.assertTrue(fields <= data.keys())
                self.assertTrue(data["source"].strip())
                timestamp = datetime.fromisoformat(data["timestamp"])
                self.assertEqual(timestamp.utcoffset(), timedelta(0))

        for exception, status in ((PermissionError, "DEGRADED"), (OSError, "ERROR")):
            with self.subTest(status=status), patch(
                "raspberry.mcp_server.device_observations.psutil.virtual_memory", side_effect=exception,
            ):
                self.assertEqual(self.capabilities()["get_memory_info"], (status, "device"))
                result = self.call("get_memory_info")
                self.assertTrue(result["isError"])
                data = result["structuredContent"]
                self.assertEqual(data["status"], status.lower())
                self.assertTrue(data["error_code"])
                self.assertTrue(any(data["message"] in block.get("text", "") for block in result["content"]))

    def test_wireless_and_planned_tools_without_a_source(self):
        self.initialize()
        for name, status in (("get_access_points", "degraded"), ("analyze_packet_capture", "unavailable")):
            with self.subTest(name=name):
                result = self.call(name)
                self.assertTrue(result["isError"])
                data = result["structuredContent"]
                self.assertEqual(data["status"], status)
                self.assertEqual(data["error_code"], "CAPABILITY_UNAVAILABLE")
                self.assertIsNone(data["data"])
                self.assertTrue(any(data["message"] in block.get("text", "") for block in result["content"]))

    def test_kismet_status_and_datasources(self):
        self.initialize()
        result = self.call("get_kismet_status")
        self.assertFalse(result["isError"], result)
        self.assertTrue(result["structuredContent"]["running"])
        result = self.call("get_kismet_datasources")
        self.assertFalse(result["isError"], result)
        self.assertEqual(result["structuredContent"]["datasources"], [])
        snapshot = self.call("get_capability_status")["structuredContent"]["kismet"]
        self.assertEqual(snapshot["version"], "2025-09-R1")
        self.assertEqual(snapshot["datasource_count"], 0)

        # A discovery snapshot does not authorize subsequent calls after the upstream API fails.
        del self.api["GET", "/datasource/all_sources.json"]
        failed = self.call("get_kismet_datasources")
        self.assertTrue(failed["isError"], failed)
        self.assertEqual(failed["structuredContent"]["status"], "error")
        self.assertEqual(self.capabilities()["get_kismet_datasources"], ("ERROR", "kismet"))

    def test_unregistered_device_cannot_discover_or_call_tools(self):
        for token in (None, self.shared_token, "u" * 43):
            headers = {"Accept": self.headers["Accept"]}
            if token is not None:
                headers["Authorization"] = f"Bearer {token}"
            for method, params in (
                ("tools/list", {}),
                ("tools/call", {"name": "get_system_info", "arguments": {}}),
                ("tools/call", {"name": "get_capability_status", "arguments": {}}),
            ):
                response = self.client.post("/mcp", headers=headers, json={
                    "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
                })
                self.assertEqual(response.status_code, 401)

    def test_operator_requires_active_enrollment_and_checks_host_before_action(self):
        url = "/operator/radio/wifi-scan"
        with patch("raspberry.mcp_server.phone_radio.radio_action", return_value={"wifi": {"state": "starting"}}) as start:
            self.assertEqual(self.client.post(url).status_code, 401)
            self.assertEqual(self.client.post(url, headers={**self.headers, "Host": "other"}).status_code, 421)
            self.assertEqual(self.client.post(url, headers=self.headers, json={"extra": True}).status_code, 400)
            start.assert_not_called()
            self.assertEqual(self.client.post(url, headers=self.headers, json={}).status_code, 200)
            start.assert_called_once_with("wifi-scan")
            self.registry.revoke(self.device_id, lambda _: None)
            self.assertEqual(self.client.post(url, headers=self.headers).status_code, 401)
            self.assertEqual(self.client.get("/operator/replay/status", headers=self.headers).status_code, 401)
            self.assertEqual(start.call_count, 1)


if __name__ == "__main__":
    unittest.main()
