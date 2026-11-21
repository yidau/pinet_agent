import struct
import tempfile
import unittest
import uuid
from pathlib import Path
from unittest.mock import Mock, patch

import httpx
from starlette.applications import Starlette

from raspberry.mcp_server import file_sources as files
from raspberry.mcp_server import phone_captures, source_control


class PhoneCaptureTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.phone = self.root / files.PHONE_DIRECTORY
        self.phone.mkdir(0o750)
        self.staging = self.phone / files.UPLOAD_STAGING
        self.staging.mkdir(0o700)
        patcher = patch.object(files, "CAPTURE_OWNER_UID", self.root.stat().st_uid)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.service = Mock()
        app = Starlette(routes=phone_captures.capture_routes(self.service, self.root))
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app), base_url="http://test")
        self.addAsyncCleanup(self.client.aclose)
        self.pcap = b"\xd4\xc3\xb2\xa1" + struct.pack("<HHIIII", 2, 4, 0, 0, 65535, 105)

    async def upload(self, name, data):
        return await self.client.put("/operator/captures/" + name, content=data,
                                     headers={"Content-Type": "application/octet-stream"})

    async def test_import_stream_appears_once_after_validation(self):
        async def chunks():
            yield self.pcap[:12]
            self.assertEqual(files.list_files(self.root), [])
            second = await self.upload("second.pcap", self.pcap)
            self.assertEqual(second.status_code, 409)
            yield self.pcap[12:]

        response = await self.upload("LAB.PCAP", chunks())
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(files.capture_metadata("LAB.PCAP", self.root), response.json())
        self.assertEqual(files.list_files(self.root), [response.json()])
        self.assertEqual((await self.upload("LAB.PCAP", self.pcap)).status_code, 409)
        self.assertEqual((self.phone / "LAB.PCAP").read_bytes(), self.pcap)
        (self.root / "existing.pcap").write_bytes(self.pcap)
        self.assertEqual((await self.upload("existing.pcap", self.pcap)).status_code, 409)
        self.assertEqual(list(self.staging.iterdir()), [])

    async def test_partial_invalid_and_large_imports_do_not_publish(self):
        self.assertEqual((await self.upload("bad.pcap", b"wrong")).status_code, 400)
        self.assertEqual((await self.upload("x.kismet", b"x")).status_code, 400)
        with patch.object(files, "MAX_BYTES", 10):
            self.assertEqual((await self.upload("huge.pcap", self.pcap)).status_code, 413)
            async def chunks():
                yield self.pcap[:8]
                yield self.pcap[8:]
            self.assertEqual((await self.upload("huge.pcap", chunks())).status_code, 413)
        self.assertEqual(list(self.staging.iterdir()), [])
        self.assertEqual(files.list_files(self.root), [])
        with patch.object(files, "MAX_FILES", 1):
            (self.root / "existing.pcap").write_bytes(self.pcap)
            self.assertEqual((await self.upload("b.pcap", self.pcap)).status_code, 409)

    async def test_routes_require_confirmation_and_keep_legacy_policy(self):
        input_data = {"capture_id": "lab.pcap", "confirm": True}
        with patch.object(files, "control", return_value={"state": "running"}) as control:
            for data in ({"capture_id": "lab.pcap"}, {**input_data, "confirm": 1}, {**input_data, "extra": 1},
                         {**input_data, "capture_id": "../a.pcap"}):
                self.assertEqual((await self.client.post("/operator/replay/start", json=data)).status_code, 400)
            self.assertFalse(control.called)
            self.assertEqual((await self.client.post("/operator/replay/start", json=input_data)).status_code, 200)
            control.assert_called_once_with("phone-start", "lab.pcap")
            await self.client.post("/operator/replay/stop", json={"confirm": True})
            control.assert_called_with("stop")
        self.service.call.return_value = {"state": "completed", "total_devices": 1}
        self.assertEqual((await self.client.get("/operator/replay/status")).json(), self.service.call.return_value)
        self.service.call.assert_called_once_with("get_capture_status")
        with patch.object(source_control, "ALLOW_REPLAY", self.root / "absent"):
            replay = source_control.Replay.__new__(source_control.Replay)
            with self.assertRaisesRegex(files.SourceError, "not been enabled"):
                replay.execute({"action": "start", "capture_id": "lab.pcap"})
            with self.assertRaisesRegex(files.SourceError, "enrolled-phone gateway"):
                replay.execute({"action": "phone-start", "capture_id": "lab.pcap"})

    async def test_confirmed_replay_resolves_imported_file_without_global_opt_in(self):
        name = "phone.pcap"
        self.assertEqual((await self.upload(name, self.pcap)).status_code, 201)
        ident = str(uuid.uuid5(uuid.NAMESPACE_URL, "urn:piagent:offline:" + name)).upper()
        api = Mock()
        api.get_datasources.side_effect = [[], [{"uuid": ident, "name": "PocketNet-file-" + ident,
                                                 "driver": "pcapfile", "running": True, "error": False}]]
        with (patch.object(source_control, "ALLOW_REPLAY", self.root / "absent"),
              patch.object(source_control, "STATE_FILE", self.staging / "replay-state.json"),
              patch.object(source_control, "CAPTURES", self.root),
              patch.object(source_control, "capture_metadata", side_effect=lambda n: files.capture_metadata(n, self.root)),
              patch.object(source_control.shutil, "which", return_value="/usr/bin/kismet_cap_pcapfile")):
            replay = source_control.Replay(api)
            result = replay.execute({"action": "phone-start", "capture_id": name}, phone_operator=True)
            self.assertEqual(result["state"], "running")
            self.assertTrue(api.command.call_args.args[1]["definition"].startswith(f"{self.phone / name}:type=pcapfile,"))
