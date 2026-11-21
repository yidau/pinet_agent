"""C1/C3/C5/C6. Synthetic headers and mock Kismet responses; no radios or real capture."""

import json
import os
from pathlib import Path
import sqlite3
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

from raspberry.mcp_server import file_sources as files
from raspberry.mcp_server import source_control
from raspberry.mcp_server.capabilities import CapabilityStatus as State
from raspberry.mcp_server.kismet_adapter import KismetAdapter, KismetError


class FileSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        # Per-test directories are owned by the runner rather than the deployment administrator.
        if os.name == "posix" and os.getuid() != 0:
            patcher = patch.object(files, "CAPTURE_OWNER_UID", os.getuid())
            patcher.start()
            self.addCleanup(patcher.stop)

    def pcap(self):
        path = self.directory / "demo.pcap"
        path.write_bytes(b"\xd4\xc3\xb2\xa1" + struct.pack("<HHIIII", 2, 4, 0, 0, 65535, 105))
        return path

    def test_c6_formats_and_directory_boundaries(self):
        self.pcap()
        (self.directory / "demo.pcapng").write_bytes(
            b"\x0a\x0d\x0d\x0a" + struct.pack("<IIHHqI", 28, 0x1A2B3C4D, 1, 0, -1, 28))
        db = sqlite3.connect(self.directory / "demo.kismet")
        db.executescript("CREATE TABLE KISMET(db_version); INSERT INTO KISMET VALUES(9);"
                         "CREATE TABLE packets(packet); CREATE TABLE data(json);")
        db.close()
        self.assertEqual({r["format"] for r in files.list_files(self.directory)}, {"PCAP","PCAPNG","KismetDB"})
        for name in ("../demo.pcap", "/etc/passwd", "C:\\a.pcap", "x:pps=0.pcap", "missing.pcap"):
            with self.subTest(name=name), self.assertRaises(files.SourceError):
                files.capture_metadata(name, self.directory)
        (self.directory / "bad.pcapng").write_bytes(b"SQLite format 3\0")
        self.assertEqual(next(r for r in files.list_files(self.directory) if r["id"] == "bad.pcapng")["status"], "ERROR")
        link = self.directory / "other.pcap"
        os.link(self.directory / "demo.pcap", link)
        with self.assertRaises(files.SourceError):
            files.capture_metadata(link.name, self.directory)

    def test_c1_seenby_phy_filter_and_bluetooth_separation(self):
        adapter = KismetAdapter()
        device = {"kismet.device.base.key": "key", "kismet.device.base.type": "BTLE",
                  "kismet.device.base.macaddr": "01:23:45:67:89:ab", "kismet.device.base.phyname": "Bluetooth",
                  "kismet.device.base.signal":{"kismet.common.signal.type":"dbm","kismet.common.signal.last_signal":-65},
                  "kismet.device.base.seenby":{"1":{"kismet.common.seenby.uuid":files.BT_UUID}},
                  "service_uuids":["180F"]}
        adapter._request = Mock(return_value={"data":[device], "recordsFiltered":1})
        result, total = adapter.get_source_devices(files.BT_UUID, phy="Bluetooth")
        url, form = adapter._request.call_args.args
        self.assertEqual(url, f"/devices/views/seenby-{files.BT_UUID}/devices.json")
        self.assertIn(["kismet.device.base.phyname", "^Bluetooth$"], json.loads(form["json"])["regex"])
        self.assertEqual((total, result[0]["rssi_dbm"], result[0]["service_uuids"]), (1, -65, ["180F"]))
        device["kismet.device.base.seenby"]["2"] = {"kismet.common.seenby.uuid":"00000000-0000-0000-0000-000000000000"}
        result, _ = adapter.get_source_devices(files.BT_UUID, phy="Bluetooth")
        self.assertIsNone(result[0]["rssi_dbm"])
        self.assertNotIn("service_uuids", result[0])
        device["kismet.device.base.seenby"]["1"]["kismet.common.seenby.signal"] = {
            "kismet.common.signal.type":"dbm","kismet.common.signal.last_signal":-75}
        result, _ = adapter.get_source_devices(files.BT_UUID, phy="Bluetooth")
        self.assertEqual(result[0]["rssi_dbm"], -75)
        del device["kismet.device.base.seenby"]
        result, _ = adapter.get_source_devices(files.BT_UUID, phy="Bluetooth")
        self.assertIsNone(result[0]["type"])
        self.assertIsNone(result[0]["rssi_dbm"])
        device["kismet.device.base.phyname"] = "IEEE802.11"
        with self.assertRaises(KismetError):
            adapter.get_source_devices(files.BT_UUID, phy="Bluetooth")

    def test_c3_source_states_empty_valid_missing_and_unconfirmed(self):
        service = files.SourceService(Mock(), self.directory)
        with patch.object(files.shutil, "which", return_value=None):
            states, features = service.capabilities([])
        self.assertEqual((states["list_captures"][0], features["pcap_replay"]["status"]),
                         (State.AVAILABLE, State.DEGRADED))
        self.pcap()
        with self.assertRaisesRegex(files.SourceError, "confirmation"):
            service.call("replay_capture", [], capture_id="demo.pcap")
        self.assertEqual(service.call("list_captures", None)["captures"][0]["size_bytes"], 24)
        states, _ = service.capabilities(None)
        self.assertEqual(states["replay_capture"][0], State.ERROR)

    def test_c1_file_start_uses_bounded_definition_and_closes_at_eof(self):
        api = Mock()
        path = self.pcap()
        ident = str(source_control.uuid.uuid5(source_control.uuid.NAMESPACE_URL, "urn:piagent:offline:" + path.name)).upper()
        row = {"uuid":ident, "name":"PocketNet-file-"+ident, "driver":"pcapfile", "running":True,
               "error":False, "interface": str(path)}
        api.get_datasources.side_effect = [[], [row], [row]]
        api.eof_event.return_value = "completed"
        with (patch.object(source_control, "STATE_FILE", self.directory / "state.json"),
              patch.object(source_control, "ALLOW_REPLAY", path),
              patch.object(source_control, "CAPTURES", self.directory),
              patch.object(source_control, "capture_metadata", side_effect=lambda n: files.capture_metadata(n, self.directory)),
              patch.object(source_control.shutil, "which", return_value="/usr/bin/kismet_cap_pcapfile")):
            run = source_control.Replay(api)
            self.assertEqual(run.execute({"action":"start","capture_id":path.name})["state"], "running")
            args = api.command.call_args.args
            self.assertEqual(args[0], "/datasource/add_source.cmd")
            self.assertTrue(args[1]["definition"].endswith("pps=50,retry=false"))
            run.poll()
            self.assertEqual(run.data["state"], "completed")
            api.command.assert_called_with(f"/datasource/by-uuid/{ident}/close_source.cmd")
