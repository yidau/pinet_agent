import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from jsonschema import Draft202012Validator
from starlette.testclient import TestClient

from raspberry.enrollment.registry import Registry
from raspberry.mcp_server.sandbox import DockerSandbox
from raspberry.mcp_server.server import create_app
from raspberry.mcp_server.workspace import Workspace


class WorkspaceTests(unittest.TestCase):
    def test_links_and_traversal_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            outside = root / "outside.txt"
            outside.write_text("private")
            workspace = Workspace(root / "workspace")
            for path in ("../outside.txt", str(outside), "project/../../outside.txt"):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    workspace.read_file(path)

            link = workspace.root / "linked.txt"
            link.hardlink_to(outside)
            with self.assertRaises(ValueError):
                workspace.read_file("linked.txt")
            with self.assertRaises(ValueError):
                workspace.write_file("linked.txt", "changed")
            self.assertEqual(outside.read_text(), "private")


class McpTests(unittest.TestCase):
    def test_authenticated_tool_flow_and_boundary(self):
        token = "test-token-for-local-use-only-12345"
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json, text/event-stream",
        }
        with tempfile.TemporaryDirectory() as directory:
            app = create_app(Path(directory), token, ["testserver"], DockerSandbox("piagent-builder:0.1"))
            with TestClient(app) as client:
                self.assertEqual(client.post("/mcp", json={}).status_code, 401)
                self.assertEqual(client.post("/mcp", headers={**headers, "Host": "other"}, json={}).status_code, 421)
                self.assertEqual(
                    client.post("/mcp", headers={**headers, "Origin": "https://other.example"}, json={}).status_code,
                    403,
                )

                def request(method, params=None, *, notification=False):
                    body = {"jsonrpc": "2.0", "method": method}
                    if not notification:
                        body["id"] = 1
                    if params is not None:
                        body["params"] = params
                    response = client.post("/mcp", headers=headers, json=body)
                    self.assertEqual(response.status_code, 202 if notification else 200, response.text)
                    return None if notification else response.json()["result"]

                initialized = request("initialize", {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {"name": "integration-test", "version": "1"},
                })
                headers["MCP-Protocol-Version"] = initialized["protocolVersion"]
                request("notifications/initialized", notification=True)
                names = {tool["name"] for tool in request("tools/list")["tools"]}
                self.assertTrue({"get_system_info", "compile_project", "run_tests"} <= names)
                self.assertFalse({"delete_file", "git_push", "execute_shell"} & names)

                def call(tool_name, **arguments):
                    return request("tools/call", {"name": tool_name, "arguments": arguments})

                self.assertTrue(call("get_system_info")["structuredContent"]["os"])
                self.assertTrue(call("create_project", name="queue")["structuredContent"]["created"])
                call("write_file", path="queue/main.cpp", content="int main() { return 0; }")
                self.assertFalse(call("create_project", name="queue")["structuredContent"]["created"])
                result = call("read_file", path="queue/main.cpp")["structuredContent"]
                self.assertEqual(result["content"], "int main() { return 0; }")
                self.assertTrue(call("read_file", path="../outside.txt")["isError"])
                if sys.platform != "linux":
                    blocked = call("compile_project", name="queue")
                    self.assertTrue(blocked["isError"])
                    self.assertIn("rootless Docker", blocked["content"][0]["text"])


class DeviceMcpTests(unittest.TestCase):
    STATUS_FIELDS = {
        "get_system_info": {"hostname", "os", "kernel", "architecture"},
        "get_cpu_info": {"logical_cores", "used_percent", "temperature_c"},
        "get_memory_info": {"total_bytes", "available_bytes", "used_percent"},
        "get_disk_usage": {"total_bytes", "used_bytes", "free_bytes", "used_percent"},
    }
    LEGACY_PARAMETERS = {
        "list_files": {"path"},
        "read_file": {"path"},
        "create_directory": {"path"},
        "create_project": {"name"},
        "write_file": {"path", "content"},
        "compile_project": {"name"},
        "run_tests": {"name"},
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
        app = create_app(root / "workspace", self.shared_token, ["testserver"],
                         DockerSandbox("unused"), registry.database)
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
            "clientInfo": {"name": "PiAgent mobile", "version": "0.4.0"},
        })
        self.assertEqual(result["serverInfo"]["name"], "PiAgent")
        self.headers["MCP-Protocol-Version"] = result["protocolVersion"]
        self.request("notifications/initialized", notification=True)

    def call(self, name, arguments=None):
        return self.request("tools/call", {"name": name, "arguments": arguments or {}})

    def test_authorized_device_discovers_and_calls_registered_tools(self):
        self.initialize()
        tools = self.request("tools/list")["tools"]
        names = [tool["name"] for tool in tools]
        self.assertCountEqual(names, [*self.STATUS_FIELDS, *self.LEGACY_PARAMETERS])
        for tool in tools:
            name = tool["name"]
            with self.subTest(tool=name):
                self.assertTrue(tool["description"].strip())
                schema = tool["inputSchema"]
                Draft202012Validator.check_schema(schema)
                self.assertEqual(schema["type"], "object")
                properties = schema.get("properties", {})
                if name in self.STATUS_FIELDS:
                    self.assertTrue(tool["annotations"]["readOnlyHint"])
                    self.assertFalse(properties)
                    self.assertFalse(schema["additionalProperties"])
                    self.assertTrue(self.call(name, {"unexpected": 1})["isError"])
                    result = self.call(name)
                    self.assertFalse(result["isError"])
                    data = result["structuredContent"]
                    self.assertTrue(self.STATUS_FIELDS[name] <= data.keys())
                    self.assertTrue(data["source"].strip())
                    timestamp = datetime.fromisoformat(data["timestamp"])
                    self.assertEqual(timestamp.utcoffset(), timedelta(0))
                else:
                    parameters = self.LEGACY_PARAMETERS[name]
                    self.assertEqual(set(properties), parameters)
                    self.assertTrue(all(value["type"] == "string" for value in properties.values()))
                    if name == "list_files":
                        self.assertEqual(properties["path"]["default"], ".")
                        self.assertFalse(schema.get("required"))
                    else:
                        self.assertEqual(set(schema["required"]), parameters)

    def test_observation_error_uses_mcp_error_result(self):
        self.initialize()
        with patch("raspberry.mcp_server.device_observations.psutil.virtual_memory", side_effect=OSError):
            result = self.call("get_memory_info")
        self.assertTrue(result["isError"])
        error = result["structuredContent"]["error"]
        self.assertTrue(error["type"])
        self.assertTrue(error["message"])
        self.assertIsInstance(error["retryable"], bool)
        self.assertTrue(any(error["message"] in block.get("text", "") for block in result["content"]))

    def test_unregistered_device_cannot_discover_or_call_tools(self):
        for token in (None, self.shared_token, "u" * 43):
            headers = {"Accept": self.headers["Accept"]}
            if token is not None:
                headers["Authorization"] = f"Bearer {token}"
            for method, params in (
                ("tools/list", {}),
                ("tools/call", {"name": "get_system_info", "arguments": {}}),
            ):
                response = self.client.post("/mcp", headers=headers, json={
                    "jsonrpc": "2.0", "id": 1, "method": method, "params": params,
                })
                self.assertEqual(response.status_code, 401)


if __name__ == "__main__":
    unittest.main()
