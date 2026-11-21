"""Handset control of the two fixed, bounded systemd radio jobs."""

import re
import socket
import subprocess
import sys
import time
from pathlib import Path


SOCKET = "/run/piagent-phone-radio.sock"
WIFI = "piagent-managed-scan@shared-ap.service"
BLUETOOTH = "piagent-bluetooth-scan.service"
ACTIONS = {
    "wifi-scan": ("start", WIFI),
    "bluetooth-start": ("start", BLUETOOTH),
    "bluetooth-stop": ("stop", BLUETOOTH),
}
BT_CONFLICT = Path("/etc/piagent-sources/bluetooth-conflict")
PROPERTIES = ("Id,LoadState,ActiveState,Result,ExecStartPre,ExecMainCode,ExecMainStatus,ActiveEnterTimestampMonotonic,"
              "ExecMainStartTimestampMonotonic,ExecMainExitTimestampMonotonic")
BT_PREFLIGHT_ERRORS = {
    69: "无法读取树莓派的蓝牙控制器 hci0。",
    75: "读取蓝牙控制器设置超时，请稍后重试。",
    78: "蓝牙控制器地址或运行模式不符合要求。请确认控制器已开启并支持 LE 和 BR/EDR。",
    76: "无法读取 BlueZ 的设备发现状态，请稍后重试。",
    73: "蓝牙控制器正在执行其他发现任务，等该任务结束后再试。",
}


class RadioError(Exception):
    def __init__(self, message, status_code=503):
        self.status_code = status_code
        super().__init__(message)


def _systemctl(*args):
    return subprocess.run(
        ["/usr/bin/systemctl", "--system", "--no-pager", "--no-ask-password", *args],
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=4, check=False,
    )


def _units():
    try:
        response = _systemctl("show", "--all", "--property=" + PROPERTIES, WIFI, BLUETOOTH)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RadioError("无法读取树莓派的无线服务状态。") from exc
    # systemctl can also return individual not-found units in its output.
    result = {}
    for block in response.stdout.strip().split("\n\n"):
        fields = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        if fields.get("Id"):
            result[fields["Id"]] = fields
    if not result:
        raise RadioError("无法读取树莓派的无线服务状态。")
    return result


def _job_failure(unit, *, bluetooth=False):
    # Only expose systemd result codes; pre-start command lines and journal
    # output can contain deployment-specific arguments and credentials.
    result = unit.get("Result")
    if result == "timeout":
        return "服务超时。"
    if result == "start-limit-hit":
        return "启动次数已达上限，请稍后重试。"
    if result in ("signal", "core-dump", "oom-kill"):
        return "服务进程被系统终止。"
    pre = re.search(r"\bcode=exited\s*;\s*status=(\d+)\b", unit.get("ExecStartPre", ""))
    if pre and int(pre[1]) != 0:
        if pre[1] == "200":
            return "服务无法进入工作目录（200/CHDIR）。"
        if bluetooth and int(pre[1]) in BT_PREFLIGHT_ERRORS:
            return BT_PREFLIGHT_ERRORS[int(pre[1])]
        return f"启动前检查退出，退出码 {pre[1]}。"
    status = unit.get("ExecMainStatus", "")
    if unit.get("ExecMainCode") == "1" and status.isdecimal() and int(status) != 0:
        if status == "200":
            return "服务无法进入工作目录（200/CHDIR）。"
        return f"服务进程退出，退出码 {status}。"
    return "服务启动或执行失败。"


def _wifi_status(unit, scan):
    state = unit.get("ActiveState")
    if unit.get("LoadState") != "loaded":
        return {"state": "error", "reason": "树莓派缺少普通 Wi-Fi 扫描服务。"}
    if state in ("activating", "active", "deactivating"):
        return {"state": "running", "reason": ""}
    if state == "failed":
        detail = _job_failure(unit)
        terminal_report = scan.get("source_uuid") and not scan.get("observed_at") and not scan.get("in_progress")
        if scan["status"] == "ERROR" or terminal_report:
            detail += "扫描报告：" + scan["reason"]
        else:
            detail += "未取得本次扫描的完成报告。"
        return {"state": "error", "reason": detail}
    if scan.get("in_progress"):
        return {"state": "running", "reason": ""}
    if scan["status"] == "ERROR":
        return {"state": "error", "reason": scan["reason"]}
    if scan["status"] == "AVAILABLE":
        return {"state": "completed", "reason": "", "observed_at": scan.get("observed_at"),
                "access_point_count": len(scan["access_points"]), "submitted_count": scan["submitted_count"]}
    if scan.get("source_uuid") and not scan.get("observed_at"):
        return {"state": "error", "reason": scan["reason"]}
    if scan.get("observed_at"):
        return {"state": "idle", "reason": "上次扫描结果已过期，点「扫描 Wi-Fi」可重新扫描。"}
    return {"state": "idle", "reason": "暂无近期扫描结果，点「扫描 Wi-Fi」开始。"}


def _bluetooth_status(unit):
    if unit.get("LoadState") != "loaded":
        return {"state": "error", "reason": "树莓派缺少蓝牙发现服务。"}
    state = unit.get("ActiveState")
    if state == "active":
        since = int(unit.get("ActiveEnterTimestampMonotonic") or 0) / 1_000_000
        remaining = max(0, min(120, 120 - int(time.monotonic() - since)))
        return {"state": "running", "reason": "", "remaining_seconds": remaining}
    if state in ("activating", "deactivating"):
        return {"state": "starting" if state == "activating" else "stopping", "reason": ""}
    start = int(unit.get("ExecMainStartTimestampMonotonic") or 0)
    end = int(unit.get("ExecMainExitTimestampMonotonic") or 0)
    if unit.get("Result") == "timeout" and start and end - start >= 119_000_000:
        return {"state": "completed", "reason": "两分钟蓝牙发现已结束。"}
    if state == "failed":
        return {"state": "error", "reason": _job_failure(unit, bluetooth=True)}
    if BT_CONFLICT.exists():
        return {"state": "error", "reason": "设备已标记蓝牙发现与校时冲突。"}
    return {"state": "stopped" if start else "idle", "reason": ""}


def radio_status():
    from .managed_scan import read_managed_scan

    units = _units()
    return {"wifi": _wifi_status(units.get(WIFI, {}), read_managed_scan()),
            "bluetooth": _bluetooth_status(units.get(BLUETOOTH, {}))}


def radio_action(action):
    if action not in ACTIONS:
        raise RadioError("未知的无线操作。", 400)
    if action == "bluetooth-start" and BT_CONFLICT.exists():
        raise RadioError("设备已标记蓝牙发现与校时冲突。", 409)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(6)
            client.connect(SOCKET)
            client.sendall(action.encode("ascii") + b"\n")
            with client.makefile("rb") as stream:
                response = stream.readline(128)
    except (OSError, AttributeError) as exc:
        raise RadioError("手机无线控制服务不可用。") from exc
    if response != b"OK\n":
        raise RadioError("无线服务未接受本次操作。")
    status = radio_status()
    # --no-block acknowledges the queued job. Its Activation timestamp and
    # scan snapshot can still belong to the previous run on this first read.
    radio = "wifi" if action == "wifi-scan" else "bluetooth"
    if action == "bluetooth-stop":
        if status[radio]["state"] in ("starting", "running"):
            status[radio] = {"state": "stopping", "reason": ""}
    elif status[radio]["state"] not in ("starting", "running"):
        status[radio] = {"state": "starting", "reason": ""}
    return status


def _serve_one(source, output):
    """Handle one systemd-accepted Unix socket. The peer never supplies a unit or options."""
    request = source.readline(32)
    command = next((command for action, command in ACTIONS.items()
                    if request == action.encode("ascii") + b"\n"), None)
    if command is None:
        output.write(b"INVALID\n")
        return
    try:
        result = _systemctl("--no-block", *command)
        output.write(b"OK\n" if result.returncode == 0 else b"FAILED\n")
    except (OSError, subprocess.TimeoutExpired):
        output.write(b"FAILED\n")


if __name__ == "__main__":
    _serve_one(sys.stdin.buffer, sys.stdout.buffer)
