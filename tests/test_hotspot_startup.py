"""Offline startup checks; never invoke a real service or wireless interface."""

import importlib.util
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "prepare_hotspot", ROOT / "raspberry/config/runtime/prepare-hotspot.py")
hotspot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(hotspot)


class HotspotStateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.state = self.root / "state"

    def test_new_device_starts_with_an_empty_private_psk_file(self):
        hotspot.prepare(self.state)
        path = self.state / "hostapd.psk"
        self.assertEqual(path.read_bytes(), b"")
        self.assertEqual(stat.S_IMODE(self.state.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_restart_does_not_replace_or_rewrite_registered_phone_keys(self):
        hotspot.prepare(self.state)
        path = self.state / "hostapd.psk"
        contents = b"keyid=offline-test-phone-id 00:00:00:00:00:00 offline-test-passphrase\n"
        path.write_bytes(contents)
        before = path.stat()
        hotspot.prepare(self.state)
        hotspot.prepare(self.state)
        after = path.stat()
        self.assertEqual(path.read_bytes(), contents)
        self.assertEqual((after.st_ino, after.st_mtime_ns), (before.st_ino, before.st_mtime_ns))

    def test_existing_psk_symlink_is_rejected_without_touching_its_target(self):
        self.state.mkdir(mode=0o700)
        target = self.root / "other-private-file"
        target.write_bytes(b"keep this data")
        (self.state / "hostapd.psk").symlink_to(target)
        with self.assertRaisesRegex(RuntimeError, "file is not private"):
            hotspot.prepare(self.state)
        self.assertEqual(target.read_bytes(), b"keep this data")

    def test_state_directory_symlink_is_rejected(self):
        target = self.root / "other-directory"
        target.mkdir(mode=0o700)
        self.state.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "directory is not private"):
            hotspot.prepare(self.state)
        self.assertFalse((target / "hostapd.psk").exists())

    def test_insecure_existing_state_is_rejected_without_changing_credentials(self):
        hotspot.prepare(self.state)
        path = self.state / "hostapd.psk"
        path.write_bytes(b"existing phone keys")
        path.chmod(0o644)
        with self.assertRaisesRegex(RuntimeError, "file is not private"):
            hotspot.prepare(self.state)
        self.assertEqual(path.read_bytes(), b"existing phone keys")


class FirstbootOrderTests(unittest.TestCase):
    def test_management_services_start_even_when_identity_initialization_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "app"
            commands = root / "commands"
            app.mkdir()
            commands.mkdir()
            log = root / "commands.log"

            def command(name, body):
                path = commands / name
                path.write_text("#!/bin/sh\n" + body)
                path.chmod(0o755)
                return path

            command("systemctl", 'printf "systemctl %s\\n" "$*" >> "$STARTUP_TEST_LOG"\n')
            command("hostapd_cli", 'printf "PONG\\n"\n')
            python = command("identity-python", 'printf "identity-init\\n" >> "$STARTUP_TEST_LOG"\nexit 42\n')
            epoch = root / "build-epoch"
            epoch.write_text("1700000000\n")

            # Run the real firstboot control flow, redirecting every path used
            # before the injected identity failure into this temporary tree.
            script = (ROOT / "deploy/image/firstboot.sh").read_text()
            replacements = {
                "/opt/pocketnet/current": str(app),
                "/opt/pocketnet/python/bin/python3.12": str(python),
                "/var/lib/pocketnet": str(root / "state"),
                "/etc/piagent-https": str(root / "tls"),
                "/var/lib/piagent-devices": str(root / "registry"),
                "/root/piagent-enrollment.svg": str(root / "qr.svg"),
                "/run/lock/pocketnet-firstboot.lock": str(root / "firstboot.lock"),
                "/etc/pocketnet/build-epoch": str(epoch),
                "/etc/.pocketnet-tls.pending": str(root / "tls.pending"),
            }
            for original, replacement in replacements.items():
                script = script.replace(original, replacement)
            environment = os.environ.copy()
            environment.update(PATH=f"{commands}:{os.defpath}", STARTUP_TEST_LOG=str(log))
            result = subprocess.run(["bash", "-c", script], env=environment,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 42, result.stderr)
            self.assertEqual(log.read_text().splitlines(), [
                "systemctl start piagent-hotspot.service piagent-dhcp.service", "identity-init"])
            self.assertFalse((root / "state/firstboot-complete").exists())


if __name__ == "__main__":
    unittest.main()
