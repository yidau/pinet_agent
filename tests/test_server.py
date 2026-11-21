import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from jsonschema import Draft202012Validator
from starlette.testclient import TestClient

from raspberry.enrollment.registry import Registry
from raspberry.mcp_server.server import create_app


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
    PLANNED_DOMAINS = {
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
        },
        "security_analysis": {
            "get_security_events", "detect_rogue_ap_candidates", "detect_arp_anomalies",
            "detect_ip_conflicts", "audit_wireless_security",
        },
        "network_diagnosis": {
            "diagnose_network", "investigate_network_event", "investigate_device", "generate_diagnosis_report",
        },
    }

    def setUp(self):
        root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        registry = Registry(root / "devices.sqlite3")
        registry.initialize()
        token = "d" * 43
        registry.activate(
            b"test phone public key", "test phone", register=True,
            issue_token=lambda _device: token, enable_wifi=lambda _credential: None,
        )
        self.shared_token = "s" * 32
        app = create_app(root, self.shared_token, ["testserver"], registry.database)
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
            "clientInfo": {"name": "PocketNet AI", "version": "0.5.0"},
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
        for domain, names in self.PLANNED_DOMAINS.items():
            expected.update({name: ("UNAVAILABLE", domain) for name in names})

        tools = self.request("tools/list")["tools"]
        self.assertCountEqual([tool["name"] for tool in tools], expected.keys())
        self.assertEqual(self.capabilities(), expected)
        for tool in tools:
            with self.subTest(tool=tool["name"]):
                self.assertTrue(tool["description"].strip())
                schema = tool["inputSchema"]
                Draft202012Validator.check_schema(schema)
                self.assertEqual(schema["type"], "object")
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

    def test_unimplemented_wireless_tool_returns_unavailable(self):
        self.initialize()
        result = self.call("get_access_points")
        self.assertTrue(result["isError"])
        data = result["structuredContent"]
        self.assertEqual(data["status"], "unavailable")
        self.assertEqual(data["error_code"], "CAPABILITY_NOT_IMPLEMENTED")
        self.assertIsNone(data["data"])
        self.assertTrue(any(data["message"] in block.get("text", "") for block in result["content"]))

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