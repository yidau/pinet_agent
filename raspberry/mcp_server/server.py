import argparse
import hmac
import json
import logging
import os
import sqlite3
from collections.abc import Callable, Sequence
from functools import partial
from pathlib import Path
from typing import Annotated, Any

import anyio
import uvicorn
from mcp.server.fastmcp import FastMCP
from mcp.server.fastmcp.exceptions import ToolError
from mcp.server.transport_security import TransportSecurityMiddleware, TransportSecuritySettings
from mcp.types import CallToolResult, ContentBlock, TextContent, Tool, ToolAnnotations
from pydantic import Field
from starlette.datastructures import Headers
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse
from starlette.routing import Route
from starlette.types import ASGIApp, Receive, Scope, Send

from raspberry.enrollment.registry import Registry

from . import device_observations, phone_radio
from .phone_captures import capture_routes
from .capabilities import NETWORK_TOOLS, MUTATING_TOOLS, CapabilityStatus
from .wireless_service import WirelessError, WirelessService


AUDIT = logging.getLogger("piagent.audit")
AUDIT.setLevel(logging.INFO)
LOOPBACK = ["localhost", "localhost:*", "127.0.0.1", "127.0.0.1:*", "[::1]", "[::1]:*"]
READ_ONLY = ToolAnnotations(readOnlyHint=True, openWorldHint=False)
WRITE = ToolAnnotations(readOnlyHint=False, destructiveHint=False, openWorldHint=False)
Observation = Callable[..., dict[str, Any]]
StatusDetail = tuple[CapabilityStatus, str]
CaptureId = Annotated[str, Field(min_length=1, max_length=255, description="An id returned by list_captures.")]
Confirmation = Annotated[bool, Field(strict=True, description="Explicit operator confirmation for this operation.")]
NOT_IMPLEMENTED = "This capability is not implemented."


def _observation_error_status(error: device_observations.ObservationError) -> CapabilityStatus:
    return CapabilityStatus.ERROR if error.retryable else CapabilityStatus.DEGRADED


def _check_status(collect: Observation | None) -> StatusDetail:
    if collect is None:
        return CapabilityStatus.UNAVAILABLE, NOT_IMPLEMENTED
    try:
        collect()
    except device_observations.ObservationError as error:
        return _observation_error_status(error), str(error)
    return CapabilityStatus.AVAILABLE, ""


def _failure(
    name: str, status: CapabilityStatus, code: str, message: str, *, retryable: bool | None = None,
) -> CallToolResult:
    AUDIT.info("tool=%s outcome=%s error=%s", name, status.lower(), code)
    detail = {"status": status.lower(), "error_code": code, "message": message, "data": None}
    if retryable is not None:
        detail["error"] = {"type": code, "message": message, "retryable": retryable}
    return CallToolResult(
        isError=True, structuredContent=detail,
        content=[TextContent(type="text", text=f"{code}: {message}")],
    )


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
    device_registry: Path | None = None, *, wireless_service: WirelessService | None = None,
) -> ASGIApp:
    registry = Registry(device_registry) if device_registry is not None else None
    if registry is None and (len(token) < 32 or not token.isascii() or any(char.isspace() for char in token)):
        raise ValueError("Set PIAGENT_TOKEN to a random ASCII token of at least 32 characters")

    disk_path = workspace_path.resolve()
    wireless = wireless_service if wireless_service is not None else WirelessService()
    transport = TransportSecuritySettings(allowed_hosts=[*LOOPBACK, *hosts])
    operator_security = TransportSecurityMiddleware(transport)
    mcp = PiAgentMCP(
        "PocketNet", stateless_http=True, json_response=True, max_request_body_size=512 * 1024,
        streamable_http_path="/mcp",
        transport_security=transport,
    )
    capabilities: dict[str, tuple[str, Callable[[], StatusDetail]]] = {}

    def register(
        name: str, domain: str, description: str, collect: Observation | None = None, *,
        status: Callable[[], StatusDetail] | None = None,
        annotations: ToolAnnotations = READ_ONLY,
    ) -> None:
        async def execute(**arguments: Any) -> CallToolResult:
            if collect is None:
                return _failure(name, CapabilityStatus.UNAVAILABLE, "CAPABILITY_UNAVAILABLE", NOT_IMPLEMENTED)
            try:
                result = await anyio.to_thread.run_sync(partial(collect, **arguments))
            except WirelessError as error:
                return _failure(name, error.status, error.code, str(error))
            except device_observations.ObservationError as error:
                return _failure(name, _observation_error_status(error), error.code, str(error), retryable=error.retryable)
            AUDIT.info("tool=%s outcome=ok", name)
            return CallToolResult(
                structuredContent=result,
                content=[TextContent(type="text", text=json.dumps(result, ensure_ascii=False))],
            )

        async def without_arguments() -> CallToolResult:
            return await execute()

        async def ap_details(
            ap_id: Annotated[str, Field(min_length=1, max_length=256, description="An id from get_access_points.")],
        ) -> CallToolResult:
            return await execute(ap_id=ap_id)

        async def bluetooth_details(
            device_id: Annotated[str, Field(min_length=1, max_length=256, description="An id from get_bluetooth_devices.")],
        ) -> CallToolResult:
            return await execute(device_id=device_id)

        async def file_metadata(capture_id: CaptureId) -> CallToolResult:
            return await execute(capture_id=capture_id)

        async def replay(capture_id: CaptureId, confirm: Confirmation) -> CallToolResult:
            return await execute(capture_id=capture_id, confirm=confirm)

        async def stop_replay(confirm: Confirmation) -> CallToolResult:
            return await execute(confirm=confirm)

        handler = {
            "get_ap_details": ap_details,
            "get_bluetooth_device_details": bluetooth_details,
            "get_capture_metadata": file_metadata,
            "replay_capture": replay,
            "stop_capture_replay": stop_replay,
        }.get(name, without_arguments)
        mcp.add_tool(handler, name=name, description=description, annotations=annotations)
        capabilities[name] = domain, status or partial(_check_status, collect)

    def get_capability_status() -> dict[str, Any]:
        # A single Kismet sample feeds all dependent tools in this response.
        wireless_states, summary = wireless.snapshot()
        entries = []
        for name, (domain, probe) in capabilities.items():
            status, reason = wireless_states[name] if name in wireless.tool_names else probe()
            entry = {"name": name, "domain": domain, "status": status}
            if reason:
                entry["reason"] = reason
            entries.append(entry)
        result = {"capabilities": entries, "kismet": summary}
        if registry is not None:
            result["operator_api"] = 1
        return result

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
        "Report each registered tool's current availability and the local Kismet service and capture state.",
        get_capability_status, status=lambda: (CapabilityStatus.AVAILABLE, ""),
    )
    for domain, tools in NETWORK_TOOLS.items():
        for name, description in tools.items():
            implemented = name in wireless.tool_names
            register(
                name, domain, description if implemented else f"{description} Planned capability, currently unavailable.",
                partial(wireless.call, name) if implemented else None,
                annotations=WRITE if name in MUTATING_TOOLS else READ_ONLY,
            )

    async def radio(request: Request) -> JSONResponse:
        action = request.path_params.get("action")
        if action is not None:
            if action not in {"wifi-scan", "bluetooth-start", "bluetooth-stop"}:
                return JSONResponse({"message": "Unknown radio action."}, status_code=404)
            body = bytearray()
            async for chunk in request.stream():
                if len(body) + len(chunk) > 64:
                    return JSONResponse({"message": "Radio actions take no parameters."}, status_code=413)
                body.extend(chunk)
            if body.strip() and body.strip() != b"{}":
                return JSONResponse({"message": "Radio actions take no parameters."}, status_code=400)
        try:
            if action is None:
                data = await anyio.to_thread.run_sync(phone_radio.radio_status)
            else:
                data = await anyio.to_thread.run_sync(phone_radio.radio_action, action)
            return JSONResponse(data)
        except phone_radio.RadioError as error:
            return JSONResponse({"message": str(error)}, status_code=error.status_code)

    app = mcp.streamable_http_app()
    if registry is not None:
        app.routes.extend([
            Route("/operator/radio/status", radio, methods=["GET"]),
            Route("/operator/radio/{action}", radio, methods=["POST"]),
            *capture_routes(wireless),
        ])
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
            if scope["path"].startswith("/operator/"):
                if registry is None:
                    await JSONResponse({"message": "Phone registration required."}, status_code=403)(scope, receive, send)
                    return
                rejection = await operator_security.validate_request(Request(scope))
                if rejection is not None:
                    await rejection(scope, receive, send)
                    return
                if scope["method"] in {"POST", "PUT"}:
                    AUDIT.info("operator=%s method=%s route=%s", device_id, scope["method"],
                               scope["path"].split("/")[2])
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
