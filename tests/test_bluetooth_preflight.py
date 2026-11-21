import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from raspberry.mcp_server import source_control as bt


def event(kind, index, opcode, status=0, body=b""):
    return struct.pack("<HHHHB", kind, index, 3 + len(body), opcode, status) + body


class BluetoothPreflightTests(unittest.TestCase):
    def test_read_only_controller_info_ignores_unrelated_events(self):
        info = struct.pack("<6sBHII", b"123456", 1, 2, 0xffffffff, 0x281)
        channel = Mock()
        channel.recv.side_effect = [
            event(1, 1, 4), event(1, 0, 3), event(2, 0, 4), event(1, 0, 4, body=info),
        ]
        self.assertEqual(bt.read_controller_info(channel), (b"123456", 0x281))
        channel.sendall.assert_called_once_with(bytes.fromhex("040000000000"))

    def test_controller_error_stops_preflight(self):
        for message in (event(1, 0, 4, 0x11), event(1, 0, 4, body=b"short")):
            with self.subTest(message=message), self.assertRaises(OSError):
                bt.read_controller_info(Mock(recv=Mock(return_value=message)))
        with patch.object(bt, "controller_info", return_value=(b"123456", 0x201)), \
                patch.object(bt.subprocess, "run") as dbus, self.assertRaises(bt.BluetoothPreflightError) as error:
            bt.check_bluetooth_ready()
        self.assertEqual(error.exception.exit_status, 78)
        dbus.assert_not_called()

    def test_discovery_uses_a_read_only_dbus_property(self):
        with patch.object(bt, "controller_info", return_value=(b"123456", 0x281)), \
                patch.object(bt.subprocess, "run") as dbus:
            dbus.return_value.stdout = "b false\n"
            bt.check_bluetooth_ready()
            self.assertEqual(dbus.call_args.args[0][-5:], [
                "get-property", "org.bluez", "/org/bluez/hci0", "org.bluez.Adapter1", "Discovering",
            ])
            dbus.return_value.stdout = "b true\n"
            with self.assertRaisesRegex(bt.BluetoothPreflightError, "busy") as error:
                bt.check_bluetooth_ready()
            self.assertEqual(error.exception.exit_status, 73)
            dbus.return_value.stdout = ""
            with self.assertRaises(bt.BluetoothPreflightError) as error:
                bt.check_bluetooth_ready()
            self.assertEqual(error.exception.exit_status, 76)

    def test_controller_access_and_timeout_have_distinct_unit_exit_codes(self):
        for problem, status in ((PermissionError("denied"), 69), (TimeoutError(), 75)):
            with self.subTest(status=status), \
                    patch.object(bt.socket, "AF_BLUETOOTH", 31, create=True), \
                    patch.object(bt.socket, "BTPROTO_HCI", 1, create=True), \
                    patch.object(bt.socket, "socket", side_effect=problem), \
                    self.assertRaises(bt.BluetoothPreflightError) as error:
                bt.controller_info()
            self.assertEqual(error.exception.exit_status, status)

    def test_only_issued_credentials_are_revoked(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "issued"
            with patch.object(bt, "bt_receipt", return_value=receipt), \
                    patch.object(bt, "bt_key_name", return_value="PocketNet-BT-test"), \
                    patch.object(bt, "AdminAdapter") as adapter:
                with patch.object(bt, "check_bluetooth_ready", side_effect=SystemExit("busy")), \
                        self.assertRaises(SystemExit):
                    bt.bluetooth_prepare()
                bt.bluetooth_retire()
                adapter.assert_not_called()
                receipt.touch()
                bt.bluetooth_retire()
                self.assertFalse(receipt.exists())
                bt.bluetooth_retire()
                adapter.return_value.command.assert_called_once_with(
                    "/auth/apikey/revoke.cmd", {"name": "PocketNet-BT-test"}, text=True,
                )
