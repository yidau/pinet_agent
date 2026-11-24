"""Offline upgrade/rollback checks for management-hotspot assets."""

import ast
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


def installer_functions():
    source = (ROOT / "deploy/release/install.sh").read_text().split("<<'PYTHON'\n", 1)[1]
    source = source.rsplit("\nPYTHON", 1)[0]
    module = ast.parse(source)
    # Load definitions without invoking the live installer entry point.
    module.body = [node for node in module.body if not isinstance(node, ast.Raise)]
    namespace = {"__name__": "pocketnet_installer_fixture"}
    exec(compile(module, "deploy/release/install.sh", "exec"), namespace)
    return namespace


class HotspotReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.installer = installer_functions()

    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name) / "root"
        self.root.mkdir()
        self.release = Path(temporary.name) / "release"
        shutil.copytree(ROOT / "raspberry/config", self.release / "raspberry/config")
        self.assets = self.release / "raspberry/config/runtime"
        shutil.copyfile(ROOT / "raspberry/telemetry/piagent-telemetry.service",
                        self.assets / "piagent-telemetry.service")
        for name in ("piagent-ble-time-sync.conf", "piagent-telemetry.conf"):
            shutil.copyfile(ROOT / "deploy/systemd" / name, self.assets / name)

    def add_hotspot_assets(self):
        for name in ("piagent-hotspot.service", "piagent-dhcp.service"):
            shutil.copyfile(ROOT / "deploy/systemd" / name, self.assets / name)

    def test_existing_device_gets_units_and_boot_links_with_reversible_configuration(self):
        self.add_hotspot_assets()
        unit = self.root / "etc/systemd/system/piagent-hotspot.service"
        unit.parent.mkdir(parents=True)
        unit.write_bytes(b"previous hotspot configuration\n")
        unit.chmod(0o640)
        psk = self.root / "var/lib/piagent-enrollment/hostapd.psk"
        psk.parent.mkdir(parents=True)
        psk.write_bytes(b"existing registered phone credential\n")
        psk.chmod(0o600)

        config = self.installer["managed_configuration"](self.root, self.release)
        self.assertNotIn("var/lib/piagent-enrollment/hostapd.psk", config)
        paths = [path for path in config if path.endswith(
            ("/piagent-hotspot.service", "/piagent-dhcp.service"))]
        before = {path: self.installer["configuration_state"](self.root / path) for path in paths}
        for path in paths:
            self.installer["write_configuration"](self.root / path, config[path], before[path][1])

        for name in ("piagent-hotspot.service", "piagent-dhcp.service"):
            link = self.root / "etc/systemd/system/multi-user.target.wants" / name
            self.assertTrue(link.is_symlink())
            self.assertEqual(link.resolve(), self.root / "etc/systemd/system" / name)
            self.assertEqual(link.read_bytes(), (self.assets / name).read_bytes())
        self.assertIn("piagent-hotspot.service", self.installer["configuration_units"](paths))
        self.assertIn("piagent-dhcp.service", self.installer["configuration_units"](paths))
        self.assertEqual(psk.read_bytes(), b"existing registered phone credential\n")

        # Apply the exact rollback operation used by the installer.
        for path in reversed(paths):
            self.installer["write_configuration"](self.root / path, *before[path])
        self.assertEqual(unit.read_bytes(), b"previous hotspot configuration\n")
        self.assertEqual(unit.stat().st_mode & 0o777, 0o640)
        self.assertFalse((unit.parent / "multi-user.target.wants/piagent-hotspot.service").is_symlink())
        self.assertFalse((unit.parent / "piagent-dhcp.service").exists())
        self.assertEqual(psk.read_bytes(), b"existing registered phone credential\n")

    def test_older_release_without_hotspot_assets_remains_compatible(self):
        config = self.installer["managed_configuration"](self.root, self.release)
        self.assertFalse(any(path.endswith(("/piagent-hotspot.service", "/piagent-dhcp.service"))
                             for path in config))

    def test_helper_update_restarts_hotspot_without_treating_phone_secrets_as_assets(self):
        helper = "raspberry/config/runtime/prepare-hotspot.py"
        self.assertEqual(self.installer["changed_units"]({helper: "old"}, {helper: "new"}),
                         ["piagent-hotspot.service"])


if __name__ == "__main__":
    unittest.main()
