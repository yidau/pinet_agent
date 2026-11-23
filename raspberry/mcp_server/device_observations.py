"""Collect host device status independently of the MCP transport."""

import json
import math
import os
import platform
from datetime import UTC, datetime
from pathlib import Path

import psutil


class ObservationError(RuntimeError):
    """A collection failure that can be reported without exposing host paths."""

    def __init__(self, code: str, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.code = code
        self.retryable = retryable


def _observation(source: str, data: dict[str, object]) -> dict[str, object]:
    return {
        **data,
        "source": source,
        "timestamp": datetime.now(UTC).isoformat(timespec="seconds").replace("+00:00", "Z"),
    }


def _collection_error(code: str, subject: str, error: Exception) -> ObservationError:
    if isinstance(error, (PermissionError, psutil.AccessDenied)):
        return ObservationError(code, f"Cannot read {subject}: access denied.", retryable=False)
    if isinstance(error, FileNotFoundError):
        return ObservationError(code, f"Cannot read {subject}: data source not found.", retryable=False)
    return ObservationError(code, f"Cannot read {subject}: system query failed.", retryable=True)


def _telemetry_cache(code: str) -> tuple[dict, datetime] | None:
    location = os.environ.get("PIAGENT_TELEMETRY_SYSTEM_CACHE")
    if not location:
        return None
    try:
        with open(location, "rb") as source:
            data = json.loads(source.read(16 * 1024))
        sampled = datetime.fromtimestamp(int(data["sampled_at_ms"]) / 1000, UTC)
        if abs((datetime.now(UTC) - sampled).total_seconds()) <= 12:
            return data, sampled
    except (OSError, ValueError, TypeError, AttributeError, KeyError, OverflowError):
        pass
    raise ObservationError(code, "No fresh system observation from PiAgent telemetry.", retryable=True)


def _cache_number(data: dict, field: str) -> float | None:
    value = data.get(field)
    return value if type(value) in (int, float) and math.isfinite(value) else None


def _cached_observation(data: dict, sampled: datetime) -> dict:
    return {**data, "source": "piagent_telemetry", "timestamp": sampled.isoformat().replace("+00:00", "Z")}


def get_system_info() -> dict[str, object]:
    try:
        system = platform.uname()
        is_linux = system.system == "Linux"
        release = platform.freedesktop_os_release() if is_linux else {}
    except OSError as error:
        raise _collection_error("system_info_unavailable", "system information", error) from None
    return _observation(
        "platform.uname+os-release" if is_linux else "platform.uname",
        {
            "hostname": system.node,
            "os": release.get("PRETTY_NAME", system.system),
            "kernel": system.release,
            "architecture": system.machine,
        },
    )


def get_cpu_info() -> dict[str, object]:
    cached = _telemetry_cache("cpu_info_unavailable")
    if cached:
        data, sampled = cached
        return _cached_observation({
            "logical_cores": os.cpu_count(),
            "used_percent": _cache_number(data, "cpu_usage"),
            "temperature_c": _cache_number(data, "temperature_c"),
        }, sampled)
    try:
        temperature = None
        if hasattr(psutil, "sensors_temperatures"):
            sensors = psutil.sensors_temperatures()
            for name in ("cpu_thermal", "cpu-thermal", "soc_thermal", "coretemp", "k10temp"):
                readings = sensors.get(name)
                if readings:
                    temperature = readings[0].current
                    break
        logical_cores = psutil.cpu_count()
        used_percent = psutil.cpu_percent(interval=0.1)
    except (OSError, psutil.Error) as error:
        raise _collection_error("cpu_info_unavailable", "CPU information", error) from None
    return _observation(
        "psutil",
        {
            "logical_cores": logical_cores,
            "used_percent": used_percent,
            "temperature_c": temperature,
        },
    )


def get_memory_info() -> dict[str, object]:
    cached = _telemetry_cache("memory_info_unavailable")
    if cached:
        data, sampled = cached
        fields = ("memory_total_bytes", "memory_available_bytes")
        counts = [data.get(field) for field in fields]
        total, available = [int(value) if str(value).isascii() and str(value).isdigit() else None for value in counts]
        return _cached_observation({
            "total_bytes": total,
            "available_bytes": available,
            "used_percent": (total - available) / total * 100 if total and available is not None and available <= total else None,
        }, sampled)
    try:
        memory = psutil.virtual_memory()
    except (OSError, psutil.Error) as error:
        raise _collection_error("memory_info_unavailable", "physical memory information", error) from None
    return _observation(
        "psutil.virtual_memory",
        {
            "total_bytes": memory.total,
            "available_bytes": memory.available,
            "used_percent": memory.percent,
        },
    )


def get_disk_usage(path: Path) -> dict[str, object]:
    try:
        disk = psutil.disk_usage(str(path))
    except (OSError, psutil.Error) as error:
        raise _collection_error("disk_usage_unavailable", "workspace filesystem usage", error) from None
    return _observation(
        "psutil.disk_usage",
        {
            "total_bytes": disk.total,
            "used_bytes": disk.used,
            "free_bytes": disk.free,
            "used_percent": disk.percent,
        },
    )
