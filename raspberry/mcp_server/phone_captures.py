"""Enrolled handset file import and explicitly requested local replay."""

import errno
import json
import os
import stat
from contextlib import contextmanager
from pathlib import Path

import anyio
from starlette.requests import ClientDisconnect, Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from . import file_sources as files
from .wireless_service import WirelessError


class RequestError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


@contextmanager
def staging_file(phone):
    staging = phone / files.UPLOAD_STAGING
    info = staging.lstat()
    if not stat.S_ISDIR(info.st_mode) or (
        os.name == "posix" and (info.st_uid != os.geteuid() or info.st_mode & 0o077)
    ):
        raise files.limited("The private import staging directory is not configured.")
    lock_fd = None
    try:
        if os.name == "posix":
            import fcntl
            lock_fd = os.open(staging, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RequestError(409, "Another capture import is in progress.") from None
        # Only the lock holder can write this directory. Reclaim a previous
        # process's interrupted upload before accepting the next one.
        path = staging / "incoming.part"
        path.unlink(missing_ok=True)
        try:
            yield path
        finally:
            path.unlink(missing_ok=True)
    finally:
        if lock_fd is not None:
            os.close(lock_fd)


def publish(path, target):
    if os.name == "posix":
        # Linux renameat2 atomically publishes one complete, single-link inode
        # and preserves a destination created by another writer.
        import ctypes
        rename = ctypes.CDLL(None, use_errno=True).renameat2
        rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        if rename(-100, os.fsencode(path), -100, os.fsencode(target), 1) != 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error))
    else:
        # Windows rename already fails if the destination exists.
        os.rename(path, target)


async def import_capture(request, directory):
    name = request.path_params["filename"]
    if files.validate_name(name) not in {"PCAP", "PCAPNG"}:
        raise RequestError(400, "Select a PCAP or PCAPNG file.")
    if request.headers.get("content-type", "").partition(";")[0].strip().lower() != "application/octet-stream":
        raise RequestError(415, "Upload the original capture as application/octet-stream.")
    length = request.headers.get("content-length")
    if length is not None:
        if not length.isascii() or not length.isdecimal() or len(length) > 15:
            raise RequestError(400, "Invalid upload length.")
        length = int(length)
        if length > files.MAX_BYTES:
            raise RequestError(413, "The selected capture exceeds 64 MiB.")
    phone = files.phone_directory(directory)
    target = phone / name
    with staging_file(phone) as path:
        if os.path.lexists(target) or os.path.lexists(directory / name):
            raise RequestError(409, "A capture with this filename already exists.")
        for count, _ in enumerate(files.library_files(directory), start=1):
            if count >= files.MAX_FILES:
                raise RequestError(409, "The capture library already contains 64 files.")
        received = 0
        with path.open("xb") as stream:
            with anyio.fail_after(120):
                async for chunk in request.stream():
                    received += len(chunk)
                    if received > files.MAX_BYTES:
                        raise RequestError(413, "The selected capture exceeds 64 MiB.")
                    if chunk:
                        await anyio.to_thread.run_sync(stream.write, chunk)
            if length is not None and received != length:
                raise RequestError(400, "The capture upload was incomplete.")
            await anyio.to_thread.run_sync(stream.flush)
            os.chmod(path, 0o640)
            await anyio.to_thread.run_sync(os.fsync, stream.fileno())
        meta = files.inspect_capture(path, name, phone.stat().st_uid)
        publish(path, target)
        return meta


async def replay_request(request, fields):
    if request.headers.get("content-type", "").partition(";")[0].strip().lower() != "application/json":
        raise RequestError(415, "Expected a JSON operator command.")
    raw = bytearray()
    with anyio.fail_after(5):
        async for chunk in request.stream():
            if len(raw) + len(chunk) > 1024:
                raise RequestError(413, "Operator command is too large.")
            raw.extend(chunk)
    try:
        data = json.loads(raw)
    except (ValueError, UnicodeError):
        raise RequestError(400, "Invalid JSON operator command.") from None
    if not isinstance(data, dict) or set(data) != fields or data.get("confirm") is not True:
        raise RequestError(400, "Explicit operator confirmation is required.")
    return data


def capture_routes(wireless, directory: Path = files.CAPTURES):
    """Mount these routes only behind registered-phone authentication."""
    upload_lock = anyio.Semaphore(1)

    async def handle(request: Request):
        try:
            if request.method == "PUT":
                try:
                    upload_lock.acquire_nowait()
                except anyio.WouldBlock:
                    raise RequestError(409, "Another capture import is in progress.") from None
                try:
                    result = await import_capture(request, directory)
                finally:
                    upload_lock.release()
                return JSONResponse(result, status_code=201)
            if request.method in {"HEAD", "GET"}:
                result = await anyio.to_thread.run_sync(wireless.call, "get_capture_status")
            elif request.url.path.endswith("/start"):
                data = await replay_request(request, {"capture_id", "confirm"})
                name = data["capture_id"]
                files.validate_name(name)
                result = await anyio.to_thread.run_sync(files.control, "phone-start", name)
            else:
                await replay_request(request, {"confirm"})
                result = await anyio.to_thread.run_sync(files.control, "stop")
            return JSONResponse(result)
        except RequestError as error:
            status, reason = error.status, str(error)
        except (files.SourceError, WirelessError) as error:
            status = 400 if error.code == "INVALID_CAPTURE" else 409
            reason = str(error)
        except ClientDisconnect:
            status, reason = 400, "The upload was interrupted."
        except TimeoutError:
            status, reason = 408, "The import or operator request timed out."
        except FileExistsError:
            status, reason = 409, "A capture with this filename already exists."
        except OSError as error:
            status = 507 if error.errno in (errno.ENOSPC, errno.EDQUOT) else 503
            reason = "The capture could not be stored. Check available space and the import directory."
        return JSONResponse({"message": reason}, status_code=status)

    return [
        Route("/operator/captures/{filename}", handle, methods=["PUT"]),
        Route("/operator/replay/start", handle, methods=["POST"]),
        Route("/operator/replay/stop", handle, methods=["POST"]),
        Route("/operator/replay/status", handle, methods=["GET"]),
    ]
