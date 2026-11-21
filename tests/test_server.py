import sys
import tempfile
import unittest
from pathlib import Path

from starlette.testclient import TestClient

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


if __name__ == "__main__":
    unittest.main()
