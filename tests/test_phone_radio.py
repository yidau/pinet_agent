import io
import unittest
from unittest.mock import Mock, patch

from raspberry.mcp_server import phone_radio as radio
from raspberry.mcp_server.managed_scan import empty_state


class PhoneRadioTests(unittest.TestCase):
    def test_broker_limits_every_request_to_fixed_systemd_job(self):
        with patch.object(radio, "_systemctl", return_value=Mock(returncode=0)) as systemctl:
            for command, expected in radio.ACTIONS.items():
                with self.subTest(command=command):
                    output = io.BytesIO()
                    radio._serve_one(io.BytesIO(command.encode() + b"\n"), output)
                    systemctl.assert_called_with("--no-block", *expected)
                    self.assertEqual(output.getvalue(), b"OK\n")
            systemctl.reset_mock()
            for request in (b"wifi-scan --all\n", b"start other.service\n", b"wifi-scan", b"x" * 40 + b"\n"):
                output = io.BytesIO()
                radio._serve_one(io.BytesIO(request), output)
                self.assertEqual(output.getvalue(), b"INVALID\n")
            systemctl.assert_not_called()

    def test_wifi_uses_terminal_job_and_confirmed_kismet_scan(self):
        unit = {"LoadState": "loaded", "ActiveState": "inactive"}
        state = dict(empty_state(""), status="AVAILABLE", submitted_count=0, observed_at=115)
        self.assertEqual(radio._wifi_status(unit, state), {
            "state": "completed", "reason": "", "access_point_count": 0, "submitted_count": 0, "observed_at": 115})
        self.assertEqual(radio._wifi_status({**unit, "ActiveState": "activating"}, state)["state"], "running")
        self.assertEqual(radio._wifi_status({**unit, "ActiveState": "failed"}, state)["state"], "error")
        self.assertEqual(radio._wifi_status(unit, empty_state("not scanned"))["state"], "idle")

    def test_bluetooth_limit_and_failed_start_are_distinct(self):
        unit = {"LoadState": "loaded", "ActiveState": "failed", "Result": "timeout",
                "ExecMainStartTimestampMonotonic": "1000000", "ExecMainExitTimestampMonotonic": "121000000"}
        self.assertEqual(radio._bluetooth_status(unit)["state"], "completed")
        self.assertEqual(radio._bluetooth_status({**unit, "ExecMainExitTimestampMonotonic": "5000000"})["state"],
                         "error")
        with patch.object(radio.time, "monotonic", return_value=26):
            active = {**unit, "ActiveState": "active", "ActiveEnterTimestampMonotonic": "1000000"}
            self.assertEqual(radio._bluetooth_status(active)["remaining_seconds"], 95)

    def test_failed_wifi_without_a_report_surfaces_process_exit(self):
        unit = {"LoadState": "loaded", "ActiveState": "failed", "Result": "exit-code",
                "ExecMainCode": "1", "ExecMainStatus": "1"}
        missing = empty_state("No recent operator-authorized managed scan is available.")
        for scan in (missing, {**missing, "in_progress": True}):
            status = radio._wifi_status(unit, scan)
            self.assertEqual(status["state"], "error")
            self.assertIn("退出码 1", status["reason"])
            self.assertNotIn(missing["reason"], status["reason"])
        idle = radio._wifi_status({**unit, "ActiveState": "inactive"}, missing)
        self.assertEqual(idle["state"], "idle")
        self.assertIn("扫描 Wi-Fi", idle["reason"])

    def test_bluetooth_distinguishes_preflight_failure_without_disclosing_command(self):
        unit = {"LoadState": "loaded", "ActiveState": "failed", "Result": "exit-code",
                "ExecStartPre": "{ path=/test ; argv[]=sensitive ; code=exited ; status=1/FAILURE }"}
        status = radio._bluetooth_status(unit)
        self.assertEqual(status["state"], "error")
        self.assertIn("启动前检查", status["reason"])
        self.assertIn("退出码 1", status["reason"])
        self.assertNotIn("sensitive", status["reason"])

    def test_controller_preflight_codes_are_specific_only_to_the_precheck(self):
        unit = {"LoadState": "loaded", "ActiveState": "failed", "Result": "exit-code"}
        for code, detail in ((69, "hci0"), (75, "超时"), (78, "BR/EDR"), (76, "BlueZ"), (73, "其他发现任务")):
            with self.subTest(code=code):
                pre = {**unit, "ExecStartPre": f"{{ code=exited ; status={code} }}"}
                self.assertIn(detail, radio._bluetooth_status(pre)["reason"])
                main = {**unit, "ExecMainCode": "1", "ExecMainStatus": str(code)}
                self.assertNotIn(detail, radio._bluetooth_status(main)["reason"])
        chdir = {**unit, "ExecMainCode": "1", "ExecMainStatus": "200"}
        self.assertIn("工作目录", radio._wifi_status(chdir, empty_state("missing"))["reason"])
