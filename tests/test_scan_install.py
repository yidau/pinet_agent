import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from raspberry.config.kismet import configure, configure_sources


class ScanInstallTests(unittest.TestCase):
    def test_reinstall_repairs_ancestors_for_unprivileged_scanner(self):
        with tempfile.TemporaryDirectory() as temporary:
            env = Path(temporary) / "client.env"
            (env.parent / "managed-scan.env").write_text("PIAGENT_SCAN_KEY=fixture\n")
            with patch.object(configure, "ENV", env), patch.object(configure, "write_private"), \
                    patch.object(configure, "run") as install:
                configure.configure_scan(2501, {}, "wlan0")

        working = Path("/usr/lib/piagent-managed-scan")
        package = working / "raspberry"
        install.assert_any_call(
            "install", "-d", "-o", "root", "-g", "root", "-m", "0755",
            working, package, package / "mcp_server",
        )

    def test_bluetooth_and_replay_users_can_traverse_source_package(self):
        with patch.object(configure_sources, "run") as install:
            configure_sources.install_source_modules(Path("raspberry/mcp_server"))
        working = Path("/usr/local/lib/piagent-sources")
        package = working / "raspberry"
        install.assert_any_call(
            "install", "-d", "-o", "root", "-g", "root", "-m", "0755",
            working, package, package / "mcp_server",
        )
