import argparse
import hmac
import json
import logging
import os
import sqlite3
from collections.abc import Callable, Sequence
from functools import partial
from pathlib import Path
from typing import Any

import anyio
import uvicorn
from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.exceptions import ToolError
from mcp.server.transport_security import TransportSecuritySettings
from mcp.types import CallToolResult, ContentBlock, TextContent, Tool, ToolAnnotations
from starlette.datastructures import Headers
from starlette.responses import PlainTextResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from raspberry.enrollment.registry import Registry

from . import device_observations
from .capabilities import PLANNED_MUTATING_TOOLS, PLANNED_TOOLS, CapabilityStatus


AUDIT = logging.getLogger("piagent.audit")
AUDIT.setLevel(logging.INFO)
LOOPBACK = ["localhost", "localhost:*", "127.0.0.1", "127.0.0.1:*", "[::1]", "[::1]:*"]
READ_ONLY = ToolAnnotations(readOnlyHint=True, openWorldHint=False)
WRITE = ToolAnnotations(readOnlyHint=False, destructiveHint=False, openWorldHint=False)
Observation = Callable[[], dict[str, Any]]


def _observation_error_status(error: device_observations.ObservationError) -> CapabilityStatus:
    return CapabilityStatus.ERROR if error.retryable else CapabilityStatus.DEGRADED


def _check_status(collect: Observation | None) -> CapabilityStatus:
    if collect is None:
        return CapabilityStatus.UNAVAILABLE
    try:
        collect()
    except device_observations.ObservationError as error:
        return _observation_error_status(error)
    return CapabilityStatus.AVAILABLE


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
    workspace_path: Path, token: str, hosts: list[str],
    device_registry: Path | None = None,
) -> ASGIApp:
    registry = Registry(device_registry) if device_registry is not None else None
    if registry is None and (len(token) < 32 or not token.isascii() or any(char.isspace() for char in token)):
        raise ValueError("Set PIAGENT_TOKEN to a random ASCII token of at least 32 characters")

    disk_path = workspace_path.resolve()
    mcp = PiAgentMCP(
        "PocketNet", stateless_http=True, json_response=True, max_request_body_size=512 * 1024,
        streamable_http_path="/mcp",
        transport_security=TransportSecuritySettings(allowed_hosts=[*LOOPBACK, *hosts]),
    )
    capabilities: dict[str, tuple[str, Callable[[], CapabilityStatus]]] = {}

    def register(
        name: str, domain: str, description: str, collect: Observation | None = None, *,
        status: Callable[[], CapabilityStatus] | None = None,
        annotations: ToolAnnotations = READ_ONLY,
    ) -> None:
        async def audited() -> CallToolResult:
            if collect is None:
                message = f"{name.replace('_', ' ').capitalize()} is not implemented yet."
                AUDIT.info("tool=%s outcome=unavailable", name)
                return CallToolResult(
                    isError=True,
                    structuredContent={
                        "status": "unavailable",
                        "error_code": "CAPABILITY_NOT_IMPLEMENTED",
                        "message": message,
                        "data": None,
                    },
                    content=[TextContent(type="text", text=message)],
                )

            try:
                result = await anyio.to_thread.run_sync(collect)
            except device_observations.ObservationError as error:
                AUDIT.info("tool=%s outcome=failed error=%s", name, error.code)
                retry = "Retry may succeed." if error.retryable else "Check device configuration or permissions."
                return CallToolResult(
                    isError=True,
                    structuredContent={
                        "status": _observation_error_status(error).lower(),
                        "error_code": error.code,
                        "message": str(error),
                        "data": None,
                        "error": {"type": error.code, "message": str(error), "retryable": error.retryable},
                    },
                    content=[TextContent(type="text", text=f"{error.code}: {error} {retry}")],
                )
            AUDIT.info("tool=%s outcome=ok", name)
            return CallToolResult(
                structuredContent=result,
                content=[TextContent(type="text", text=json.dumps(result, ensure_ascii=False))],
            )

        mcp.add_tool(audited, name=name, description=description, annotations=annotations)
        capabilities[name] = domain, status or partial(_check_status, collect)

    def get_capability_status() -> dict[str, Any]:
        return {
            "capabilities": [
                {"name": name, "status": status(), "domain": domain}
                for name, (domain, status) in capabilities.items()
            ],
        }

    register(
        "get_system_info", "device",
        "Get this host's hostname, operating system release, kernel release and CPU architecture. Takes no arguments.",
        device_observations.get_system_info,
    )
    register(
        "get_cpu_info", "device",
        "Sample host CPU utilization as a percentage over 100 ms. Report logical cores and temperature "
        "in Celsius. Temperature is null without a recognized CPU sensor.",
        device_observations.get_cpu_info,
    )
    register(
        "get_memory_info", "device",
        "Get host physical memory: total bytes, available bytes and used percentage, excluding swap.",
        device_observations.get_memory_info,
    )
    register(
        "get_disk_usage", "device",
        "Get total, used and free bytes and used percentage for the filesystem containing the configured workspace.",
        partial(device_observations.get_disk_usage, disk_path),
    )
    register(
        "get_capability_status", "device",
        "Report the current availability and domain of every registered MCP tool.",
        get_capability_status, status=lambda: CapabilityStatus.AVAILABLE,
    )
    for domain, tools in PLANNED_TOOLS.items():
        for name, description in tools.items():
            register(
                name, domain, f"{description} Planned capability, currently unavailable.",
                annotations=WRITE if name in PLANNED_MUTATING_TOOLS else READ_ONLY,
            )

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
    parser = argparse.ArgumentParser(description="PocketNet MCP observation service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--allow-host", action="append", default=[], help="Allowed HTTP Host header, including port")
    parser.add_argument("--tls-cert")
    parser.add_argument("--tls-key")
    default_workspace = Path(__file__).resolve().parents[1] / "workspace"
    parser.add_argument("--workspace", type=Path, default=default_workspace, help="Filesystem path for disk observations")
    # Older service units may still include the retired sandbox image option.
    parser.add_argument("--image", help=argparse.SUPPRESS)
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
        app = create_app(args.workspace, os.environ.get("PIAGENT_TOKEN", ""), args.allow_host, args.device_registry)
    except ValueError as error:
        parser.error(str(error))
    uvicorn.run(
        app, host=args.host, port=args.port, ssl_certfile=args.tls_cert,
        ssl_keyfile=args.tls_key, proxy_headers=False, limit_concurrency=32, workers=1,
    )


if __name__ == "__main__":
    main()
