import io
import os
import re
import shutil
import stat
import tarfile
import tempfile
from pathlib import Path, PureWindowsPath
from threading import RLock

MAX_FILE_BYTES = 64 * 1024
MAX_PROJECT_BYTES = 2 * 1024 * 1024
MAX_ENTRIES = 512
MAX_DEPTH = 12
PROJECT_NAME = re.compile(r"[a-zA-Z][a-zA-Z0-9_-]{0,47}\Z")


def valid_component(name: str) -> bool:
    return (
        0 < len(name) <= 80
        and not name.startswith((".", " "))
        and not name.endswith((".", " "))
        and not PureWindowsPath(name).is_reserved()
        and all(char.isalnum() or char in " .-_" for char in name)
    )


class Workspace:
    def __init__(self, root: Path):
        root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.root = root.resolve()
        self.lock = RLock()

    @staticmethod
    def _mode(path: Path) -> int | None:
        try:
            info = path.lstat()
        except FileNotFoundError:
            return None
        if getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
            raise ValueError("Filesystem links are unavailable in the workspace")
        if stat.S_ISDIR(info.st_mode) or (stat.S_ISREG(info.st_mode) and info.st_nlink == 1):
            return info.st_mode
        raise ValueError("Only regular, unlinked workspace files and directories are supported")

    def _path(self, relative: str) -> Path:
        parts = [] if relative == "." else relative.split("/")
        if len(parts) > MAX_DEPTH or any(not valid_component(part) for part in parts):
            raise ValueError("Expected a workspace-relative path with ordinary name components")
        target = self.root
        for part in parts:
            target = target / part
            self._mode(target)
        return target

    def list_files(self, relative: str) -> list[dict[str, str]]:
        with self.lock:
            entries = []
            for entry in self._path(relative).iterdir():
                if not valid_component(entry.name):
                    continue
                try:
                    mode = self._mode(entry)
                except ValueError:
                    continue
                if mode is not None:
                    entries.append({
                        "name": entry.name,
                        "type": "directory" if stat.S_ISDIR(mode) else "file",
                    })
                if len(entries) == MAX_ENTRIES:
                    break
            return sorted(entries, key=lambda entry: entry["name"])

    @staticmethod
    def _read(path: Path) -> bytes:
        if not path.is_file():
            raise ValueError("Expected a regular file")
        with path.open("rb") as source:
            content = source.read(MAX_FILE_BYTES + 1)
        if len(content) > MAX_FILE_BYTES:
            raise ValueError("File exceeds the 64 KiB limit")
        return content

    def read_file(self, relative: str) -> str:
        with self.lock:
            return self._read(self._path(relative)).decode("utf-8")

    def write_file(self, relative: str, text: str) -> int:
        content = text.encode("utf-8")
        if len(content) > MAX_FILE_BYTES:
            raise ValueError("File exceeds the 64 KiB limit")
        with self.lock:
            target = self._path(relative)
            if target.is_dir() or not target.parent.is_dir():
                raise ValueError("Expected a file within an existing workspace directory")
            if not target.exists():
                self._check_entry_limit()
            temp = tempfile.NamedTemporaryFile(dir=target.parent, prefix=".piagent-", delete=False)
            temp_path = Path(temp.name)
            try:
                with temp:
                    temp.write(content)
                temp_path.replace(target)
            finally:
                temp_path.unlink(missing_ok=True)
        return len(content)

    def _check_entry_limit(self, extra: int = 1) -> None:
        if sum(1 for _ in self.root.rglob("*")) + extra > MAX_ENTRIES:
            raise ValueError("Workspace entry limit reached")

    def create_directory(self, relative: str) -> None:
        with self.lock:
            target = self._path(relative)
            if not target.is_dir():
                self._check_entry_limit()
                target.mkdir(mode=0o700)

    def _project_path(self, project: str) -> Path:
        if not PROJECT_NAME.fullmatch(project):
            raise ValueError("Project name must begin with an ASCII letter and use letters, digits, - or _")
        return self._path(project)

    def create_project(self, project: str) -> bool:
        with self.lock:
            target = self._project_path(project)
            if target.exists():
                cmake = self._path(f"{project}/CMakeLists.txt")
                if not cmake.is_file():
                    raise ValueError("Project name already exists without a CMakeLists.txt")
                return False
            self._check_entry_limit(extra=3)
            staging = Path(tempfile.mkdtemp(prefix=".piagent-", dir=self.root))
            try:
                (staging / "CMakeLists.txt").write_text(
                    f"cmake_minimum_required(VERSION 3.20)\nproject({project} LANGUAGES CXX)\n"
                    "set(CMAKE_CXX_STANDARD 17)\nset(CMAKE_CXX_STANDARD_REQUIRED ON)\n"
                    "set(CMAKE_CXX_EXTENSIONS OFF)\ninclude(CTest)\n"
                    f"add_executable({project} main.cpp)\n",
                    encoding="utf-8",
                )
                (staging / "main.cpp").write_text("int main() { return 0; }\n", encoding="utf-8")
                staging.rename(target)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
            return True

    def snapshot(self, project: str) -> bytes:
        with self.lock:
            root = self._project_path(project)
            if not self._path(f"{project}/CMakeLists.txt").is_file():
                raise ValueError("Project must contain a CMakeLists.txt")
            data = io.BytesIO()
            total = 0
            with tarfile.open(fileobj=data, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for count, path in enumerate(root.rglob("*"), start=1):
                    relative = path.relative_to(root)
                    if count > MAX_ENTRIES or len(relative.parts) >= MAX_DEPTH:
                        raise ValueError("Project exceeds the snapshot entry or depth limit")
                    if not all(valid_component(part) for part in relative.parts):
                        raise ValueError("Project contains an unsupported filename")
                    mode = self._mode(path)
                    if mode is None:
                        raise ValueError("Project changed while taking its snapshot")
                    member = tarfile.TarInfo(relative.as_posix())
                    if stat.S_ISDIR(mode):
                        member.type = tarfile.DIRTYPE
                        member.mode = 0o755
                        archive.addfile(member)
                        continue
                    content = self._read(path)
                    total += len(content)
                    if total > MAX_PROJECT_BYTES:
                        raise ValueError("Project exceeds the 2 MiB snapshot limit")
                    member.size = len(content)
                    member.mode = 0o644
                    archive.addfile(member, io.BytesIO(content))
            return data.getvalue()
