import argparse
import hmac
import logging
import os
import platform
import sqlite3
from functools import partial, wraps
from pathlib import Path
from typing import Annotated, Any

import anyio
import psutil
import uvicorn
from mcp.server.fastmcp import FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from mcp.types import ToolAnnotations
from pydantic import StringConstraints
from starlette.datastructures import Headers
from starlette.responses import PlainTextResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from raspberry.enrollment.registry import Registry

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


def create_app(
    workspace_path: Path, token: str, hosts: list[str], sandbox: DockerSandbox,
    device_registry: Path | None = None,
) -> ASGIApp:
    registry = Registry(device_registry) if device_registry is not None else None
    if registry is None and (len(token) < 32 or not token.isascii() or any(char.isspace() for char in token)):
        raise ValueError("Set PIAGENT_TOKEN to a random ASCII token of at least 32 characters")

    workspace = Workspace(workspace_path)
    mcp = FastMCP(
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
        """Get the execution node's OS, kernel, hostname and CPU architecture."""
        release = platform.freedesktop_os_release() if platform.system() == "Linux" else {}
        return {
            "hostname": platform.node(), "os": release.get("PRETTY_NAME", platform.system()),
            "kernel": platform.release(), "architecture": platform.machine(),
        }

    @tool(READ_ONLY)
    def get_cpu_info() -> dict[str, Any]:
        """Get CPU utilization, logical core count and Raspberry Pi CPU temperature if available."""
        temperature = None
        if hasattr(psutil, "sensors_temperatures"):
            sensors = psutil.sensors_temperatures()
            for name in ("cpu_thermal", "cpu-thermal", "soc_thermal", "coretemp", "k10temp"):
                if sensors.get(name):
                    temperature = sensors[name][0].current
                    break
        return {
            "logical_cores": psutil.cpu_count(), "used_percent": psutil.cpu_percent(interval=0.1),
            "temperature_c": temperature,
        }

    @tool(READ_ONLY)
    def get_memory_info() -> dict[str, Any]:
        """Get physical memory totals, available bytes and utilization."""
        memory = psutil.virtual_memory()
        return {"total_bytes": memory.total, "available_bytes": memory.available, "used_percent": memory.percent}

    @tool(READ_ONLY)
    def get_disk_usage() -> dict[str, Any]:
        """Get free space and utilization for the filesystem containing the workspace."""
        disk = psutil.disk_usage(str(workspace.root))
        return {
            "total_bytes": disk.total, "used_bytes": disk.used,
            "free_bytes": disk.free, "used_percent": disk.percent,
        }

    @tool(READ_ONLY)
    def list_files(path: WorkspacePath = ".") -> dict[str, Any]:
        """List visible files and directories directly under a workspace-relative path. Use . for the root."""
        return {"path": path, "entries": workspace.list_files(path)}

    @tool(READ_ONLY)
    def read_file(path: WorkspacePath) -> dict[str, Any]:
        """Read a UTF-8 text file up to 64 KiB at a workspace-relative path."""
        return {"path": path, "content": workspace.read_file(path)}

    @tool(WRITE)
    def create_directory(path: WorkspacePath) -> dict[str, Any]:
        """Create one workspace directory whose parent already exists."""
        workspace.create_directory(path)
        return {"path": path}

    @tool(WRITE)
    def create_project(name: ProjectName) -> dict[str, Any]:
        """Create a new top-level C++17 CMake scaffold. An existing project is preserved."""
        return {"path": name, "created": workspace.create_project(name)}

    @tool(OVERWRITE)
    def write_file(path: WorkspacePath, content: FileContent) -> dict[str, Any]:
        """Create or replace a UTF-8 file up to 64 KiB inside the workspace. Parent directories must exist."""
        return {"path": path, "bytes_written": workspace.write_file(path, content)}

    @tool(WRITE)
    def compile_project(name: ProjectName) -> BuildResult:
        """Configure and compile a CMake project in a fresh sandbox. Return the stage and compiler diagnostics."""
        return sandbox.run(workspace.snapshot(name), test=False)

    @tool(WRITE)
    def run_tests(name: ProjectName) -> BuildResult:
        """Build a fresh snapshot and run its CTest tests in the sandbox. Missing tests fail this tool."""
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
