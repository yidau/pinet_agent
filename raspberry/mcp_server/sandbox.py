import json
import logging
import os
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from threading import Lock
from typing import Literal
from uuid import uuid4

from pydantic import BaseModel


class BuildResult(BaseModel):
    ok: bool
    stage: Literal["setup", "configure", "build", "test", "sandbox"]
    exit_code: int | None
    timed_out: bool = False
    output: str


BUILD_SCRIPT = """
umask 077
mkdir /work/source /work/home || exit 11
tar -xf - -C /work/source || exit 11
cmake -S /work/source -B /work/build -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON || exit 12
cmake --build /work/build --parallel 1 || exit 13
if [ "$1" = test ]; then
    ctest --test-dir /work/build --output-on-failure --no-tests=error --timeout 20 || exit 14
fi
"""
STAGES = {11: "setup", 12: "configure", 13: "build", 14: "test"}
OUTPUT_BYTES = 12 * 1024
TIMEOUT = 120


class DockerSandbox:
    def __init__(self, image: str):
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9./:_@-]{0,200}", image):
            raise ValueError("Invalid sandbox image reference")
        self.image = image
        self.lock = Lock()

    def _docker(self, config: str) -> list[str]:
        if sys.platform != "linux" or os.geteuid() == 0:
            raise ValueError("Builds require a non-root Linux account and rootless Docker")
        docker = shutil.which("docker")
        socket = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.geteuid()}")) / "docker.sock"
        if not docker or not socket.is_socket():
            raise ValueError("Rootless Docker socket is unavailable")
        return [docker, "--config", config, "--host", f"unix://{socket}"]

    @staticmethod
    def _check_engine(docker: list[str]) -> None:
        try:
            response = subprocess.run(
                [*docker, "info", "--format", "{{json .}}"],
                timeout=8, capture_output=True, check=True,
            )
            info = json.loads(response.stdout)
        except (subprocess.SubprocessError, ValueError):
            raise ValueError("Unable to inspect the rootless Docker engine") from None
        options = info.get("SecurityOptions") or []
        limits = ("MemoryLimit", "SwapLimit", "CpuCfsQuota", "PidsLimit")
        if (
            info.get("CgroupVersion") != "2"
            or "name=rootless" not in options
            or not any(
                option.startswith("name=seccomp,profile=") and option != "name=seccomp,profile=unconfined"
                for option in options
            )
            or not all(info.get(limit) is True for limit in limits)
        ):
            raise ValueError("Docker must enforce rootless operation, seccomp and cgroup v2 CPU, memory and PID limits")

    def run(self, snapshot: bytes, *, test: bool) -> BuildResult:
        if not self.lock.acquire(blocking=False):
            raise ValueError("A build is already running. Retry when it completes.")
        try:
            # A blank CLI configuration prevents host proxy credentials from being injected.
            with tempfile.TemporaryDirectory(prefix="piagent-docker-") as config:
                return self._run(self._docker(config), snapshot, test)
        finally:
            self.lock.release()

    def _run(self, docker: list[str], snapshot: bytes, test: bool) -> BuildResult:
        self._check_engine(docker)
        name = f"piagent-{uuid4().hex}"
        command = [
            *docker, "run", "--rm", "--name", name, "--interactive", "--pull", "never",
            "--network", "none", "--read-only", "--cap-drop", "ALL",
            "--security-opt", "no-new-privileges", "--user", "1000:1000",
            "--memory", "512m", "--memory-swap", "512m", "--cpus", "1", "--pids-limit", "64",
            "--ulimit", "nofile=256:256", "--ulimit", "core=0:0", "--log-driver", "none",
            "--tmpfs", "/work:rw,exec,nosuid,nodev,size=160m,mode=1777",
            "--tmpfs", "/tmp:rw,nosuid,nodev,noexec,size=16m,mode=1777",
            "--env", "HOME=/work/home", "--workdir", "/work",
            "--entrypoint", "/usr/bin/timeout", self.image, "--kill-after=3s", "112s",
            "/bin/sh", "-c", BUILD_SCRIPT, "piagent",
            "test" if test else "build",
        ]
        try:
            with tempfile.TemporaryFile() as source:
                source.write(snapshot)
                source.seek(0)
                code, output = self._capture(command, source)
        finally:
            try:
                subprocess.run(
                    [*docker, "rm", "-f", name], timeout=8,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            except subprocess.TimeoutExpired:
                logging.getLogger("piagent.audit").error("docker cleanup timed out for %s", name)
        if code is None or code == 124:
            return BuildResult(ok=False, stage="sandbox", exit_code=code, timed_out=True, output=output)
        stage = ("test" if test else "build") if code == 0 else STAGES.get(code, "sandbox")
        return BuildResult(ok=code == 0, stage=stage, exit_code=code, output=output)

    @staticmethod
    def _capture(command, source) -> tuple[int | None, str]:
        output = bytearray()
        truncated = False
        limit = time.monotonic() + TIMEOUT
        with subprocess.Popen(command, stdin=source, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as process:
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    while True:
                        remaining = limit - time.monotonic()
                        if remaining <= 0 or not selector.select(remaining):
                            raise subprocess.TimeoutExpired(command, TIMEOUT)
                        chunk = os.read(process.stdout.fileno(), 8192)
                        if not chunk:
                            break
                        output.extend(chunk)
                        if len(output) > OUTPUT_BYTES:
                            del output[:-OUTPUT_BYTES]
                            truncated = True
                code = process.wait(timeout=max(0, limit - time.monotonic()))
            except subprocess.TimeoutExpired:
                code = None
            finally:
                if process.poll() is None:
                    process.kill()
        prefix = "[earlier output truncated]\n" if truncated else ""
        return code, prefix + output.decode("utf-8", errors="replace")
