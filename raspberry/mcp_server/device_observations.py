"""Collect host device status independently of the MCP transport."""

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
