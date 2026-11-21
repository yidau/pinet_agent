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
    def test_shared_token_transport_and_boundary(self):
        token = "test-token-for-local-use-only-12345"
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json, text/event-stream",
        }
        with tempfile.TemporaryDirectory() as directory:
            app = create_app(Path(directory), token, ["testserver"])
            with TestClient(app) as client:
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
            "get_kismet_devices", "get_kismet_alerts", "get_kismet_capture_status",
        },
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
        registry.activate(
            b"test phone public key", "test phone", register=True,
            issue_token=lambda _device: token, enable_wifi=lambda _credential: None,
        )
        self.shared_token = "s" * 32
        app = create_app(
            root, self.shared_token, ["testserver"], registry.database, wireless_service=WirelessService(adapter),
        )
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
            "clientInfo": {"name": "PocketNet AI", "version": "0.6.0"},
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
        self.assertEqual(self.capabilities(), expected)
        for tool in tools:
            with self.subTest(tool=tool["name"]):
                self.assertTrue(tool["description"].strip())
                schema = tool["inputSchema"]
                Draft202012Validator.check_schema(schema)
                self.assertEqual(schema["type"], "object")
                if tool["name"] == "get_ap_details":
                    self.assertEqual(schema["required"], ["ap_id"])
                    self.assertEqual(schema["properties"]["ap_id"]["type"], "string")
                else:
                    self.assertFalse(schema.get("properties"))
                self.assertFalse(schema["additionalProperties"])
        self.assertTrue(self.call("get_system_info", {"unexpected": 1})["isError"])

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


if __name__ == "__main__":
    unittest.main()
