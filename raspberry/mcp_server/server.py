import argparse
import hmac
import logging
import os
import sqlite3
from collections.abc import Sequence
from functools import partial, wraps
from pathlib import Path
from typing import Annotated, Any

import anyio
import uvicorn
from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.exceptions import ToolError
from mcp.server.transport_security import TransportSecuritySettings
from mcp.types import CallToolResult, ContentBlock, TextContent, Tool, ToolAnnotations
from pydantic import StringConstraints
from starlette.datastructures import Headers
from starlette.responses import PlainTextResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from raspberry.enrollment.registry import Registry

from . import device_observations
from .sandbox import BuildResult, DockerSandbox
from .workspace import Workspace


AUDIT = logging.getLogger("piagent.audit")
AUDIT.setLevel(logging.INFO)
LOOPBACK = ["localhost", "localhost:*", "127.0.0.1", "127.0.0.1:*", "[::1]", "[::1]:*"]
READ_ONLY = ToolAnnotations(readOnlyHint=True, openWorldHint=False)
WRITE = ToolAnnotations(readOnlyHint=False, destructiveHint=False, openWorldHint=False)
OVERWRITE = ToolAnnotations(readOnlyHint=False, destructiveHint=True, openWorldHint=False)
WorkspacePath = Annotated[str, StringConstraints(min_length=1, max_length=512)]
ProjectName = Annotated[str, StringConstraints(pattern=r"^[a-zA-Z][a-zA-Z0-9_-]{0,47}$")]
FileContent = Annotated[str, StringConstraints(max_length=65536)]


class PiAgentMCP(FastMCP):
    async def list_tools(self) -> list[Tool]:
        tools = await super().list_tools()
        for tool in tools:
            tool.inputSchema = {**tool.inputSchema, "additionalProperties": False}
        return tools

    async def call_tool(self, name: str, arguments: dict[str, Any]) -> Sequence[ContentBlock] | dict[str, Any]:
        if arguments:
            tool = next((tool for tool in await super().list_tools() if tool.name == name), None)
            # FastMCP coerces and validates known parameters but normally ignores extra keys.
            if tool is not None and arguments.keys() - tool.inputSchema.get("properties", {}).keys():
                raise ToolError(f"Unexpected arguments for {name}.")
        return await super().call_tool(name, arguments)


def create_app(
    workspace_path: Path, token: str, hosts: list[str], sandbox: DockerSandbox,
    device_registry: Path | None = None,
) -> ASGIApp:
    registry = Registry(device_registry) if device_registry is not None else None
    if registry is None and (len(token) < 32 or not token.isascii() or any(char.isspace() for char in token)):
        raise ValueError("Set PIAGENT_TOKEN to a random ASCII token of at least 32 characters")

    workspace = Workspace(workspace_path)
    mcp = PiAgentMCP(
        "PiAgent", stateless_http=True, json_response=True, max_request_body_size=512 * 1024,
        streamable_http_path="/mcp",
        transport_security=TransportSecuritySettings(allowed_hosts=[*LOOPBACK, *hosts]),
    )

    def tool(annotations: ToolAnnotations):
        def register(function):
            @wraps(function)
            async def audited(*args, **kwargs):
                name = function.__name__
                try:
                    result = await anyio.to_thread.run_sync(partial(function, *args, **kwargs))
                except device_observations.ObservationError as error:
                    AUDIT.info("tool=%s outcome=failed error=%s", name, error.code)
                    retry = "Retry may succeed." if error.retryable else "Check device configuration or permissions."
                    return CallToolResult(
                        isError=True,
                        structuredContent={
                            "error": {"type": error.code, "message": str(error), "retryable": error.retryable},
                        },
                        content=[TextContent(type="text", text=f"{error.code}: {error} {retry}")],
                    )
                except (ValueError, OSError) as error:
                    AUDIT.info("tool=%s outcome=rejected error=%s", name, type(error).__name__)
                    message = error.strerror if isinstance(error, OSError) else str(error)
                    raise ValueError(message or "Filesystem operation failed") from None
                if isinstance(result, BuildResult):
                    AUDIT.info(
                        "tool=%s outcome=%s stage=%s exit_code=%s",
                        name, "ok" if result.ok else "failed", result.stage, result.exit_code,
                    )
                else:
                    AUDIT.info("tool=%s outcome=ok", name)
                return result

            return mcp.tool(annotations=annotations)(audited)

        return register

    @tool(READ_ONLY)
    def get_system_info() -> dict[str, Any]:
        """Get this host's hostname, operating system release, kernel release and CPU architecture. Takes no arguments."""
        return device_observations.get_system_info()

    @tool(READ_ONLY)
    def get_cpu_info() -> dict[str, Any]:
        """Sample host CPU usage as a percentage over 100 ms and report logical cores and temperature in Celsius.

        Temperature is null without a recognized CPU sensor; the core count may also be unavailable.
        Takes no arguments.
        """
        return device_observations.get_cpu_info()

    @tool(READ_ONLY)
    def get_memory_info() -> dict[str, Any]:
        """Get host physical memory: total bytes, available bytes and used percentage, excluding swap. Takes no arguments."""
        return device_observations.get_memory_info()

    @tool(READ_ONLY)
    def get_disk_usage() -> dict[str, Any]:
        """Get total, used and free bytes and used percentage for the filesystem containing the configured workspace.

        Takes no arguments. Reports one filesystem, not the aggregate capacity of every disk.
        """
        return device_observations.get_disk_usage(workspace.root)

    @tool(READ_ONLY)
    def list_files(path: WorkspacePath = ".") -> dict[str, Any]:
        """List names and types of up to 512 visible entries directly inside a workspace-relative directory.

        The optional path defaults to "." for the workspace root.
        """
        return {"path": path, "entries": workspace.list_files(path)}

    @tool(READ_ONLY)
    def read_file(path: WorkspacePath) -> dict[str, Any]:
        """Read UTF-8 text from a regular file of at most 64 KiB. Requires a workspace-relative file path."""
        return {"path": path, "content": workspace.read_file(path)}

    @tool(WRITE)
    def create_directory(path: WorkspacePath) -> dict[str, Any]:
        """Create one directory at the required workspace-relative path. Its parent must already exist."""
        workspace.create_directory(path)
        return {"path": path}

    @tool(WRITE)
    def create_project(name: ProjectName) -> dict[str, Any]:
        """Create a top-level C++17 CMake project in the workspace. Requires a project name beginning with a letter.

        The result reports whether a new project was created; an existing project is preserved.
        """
        return {"path": name, "created": workspace.create_project(name)}

    @tool(OVERWRITE)
    def write_file(path: WorkspacePath, content: FileContent) -> dict[str, Any]:
        """Write UTF-8 text to a workspace-relative file and report bytes written. Requires path and content.

        The parent directory must exist. The file is created or replaced and must fit within 64 KiB.
        """
        return {"path": path, "bytes_written": workspace.write_file(path, content)}

    @tool(WRITE)
    def compile_project(name: ProjectName) -> BuildResult:
        """Configure and compile the named workspace CMake project from a snapshot in the rootless Docker sandbox.

        Requires a project name. Reports the stage, exit status and any compiler diagnostics.
        """
        return sandbox.run(workspace.snapshot(name), test=False)

    @tool(WRITE)
    def run_tests(name: ProjectName) -> BuildResult:
        """Build the named workspace CMake project from a snapshot and run its CTest suite in the rootless Docker sandbox.

        Requires a project name. Reports the stage, exit status and test diagnostics; no tests is a failure.
        """
        return sandbox.run(workspace.snapshot(name), test=True)

    app = mcp.streamable_http_app()
    expected = f"Bearer {token}".encode("ascii") if registry is None else b""

    async def authenticated(scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] == "http":
            authorization = Headers(scope=scope).get("authorization", "")
            if registry is None:
                permit = hmac.compare_digest(authorization.encode("latin-1"), expected)
            else:
                device_id = None
                if authorization.startswith("Bearer "):
                    try:
                        device_id = await anyio.to_thread.run_sync(registry.authorize, authorization[7:])
                    except (OSError, sqlite3.Error):
                        AUDIT.warning("Device authorization database unavailable")
                permit = device_id is not None
                if permit:
                    scope = {**scope, "piagent_device_id": device_id}
            if not permit:
                response = PlainTextResponse("Unauthorized", status_code=401, headers={"WWW-Authenticate": "Bearer"})
                await response(scope, receive, send)
                return
        await app(scope, receive, send)

    return authenticated


def main() -> None:
    parser = argparse.ArgumentParser(description="PiAgent MCP execution service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--allow-host", action="append", default=[], help="Allowed HTTP Host header, including port")
    parser.add_argument("--tls-cert")
    parser.add_argument("--tls-key")
    default_workspace = Path(__file__).resolve().parents[1] / "workspace"
    parser.add_argument("--workspace", type=Path, default=default_workspace)
    parser.add_argument("--image", default="piagent-builder:0.1")
    parser.add_argument("--device-registry", type=Path, default=os.environ.get("PIAGENT_DEVICE_REGISTRY") or None)
    args = parser.parse_args()
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        parser.error("Run PiAgent from an unprivileged account")
    if bool(args.tls_cert) != bool(args.tls_key):
        parser.error("Set both --tls-cert and --tls-key")
    if args.host not in ("127.0.0.1", "::1", "localhost") and (not args.tls_cert or not args.allow_host):
        parser.error("A non-loopback listener requires TLS and at least one --allow-host")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    try:
        app = create_app(args.workspace, os.environ.get("PIAGENT_TOKEN", ""), args.allow_host, DockerSandbox(args.image), args.device_registry)
    except ValueError as error:
        parser.error(str(error))
    uvicorn.run(
        app, host=args.host, port=args.port, ssl_certfile=args.tls_cert,
        ssl_keyfile=args.tls_key, proxy_headers=False, limit_concurrency=32, workers=1,
    )


if __name__ == "__main__":
    main()
