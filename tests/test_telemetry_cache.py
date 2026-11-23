import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from raspberry.mcp_server import device_observations


class TelemetryCacheTests(unittest.TestCase):
    def test_mcp_uses_only_fresh_shared_metrics_when_enabled(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / "system.json"
            sample = {
                "sampled_at_ms": str(int(time.time() * 1000)),
                "cpu_usage": 0.0,
                "memory_total_bytes": "1024",
                "memory_available_bytes": "768",
            }
            cache.write_text(json.dumps(sample), encoding="utf-8")
            with patch.dict(os.environ, {"PIAGENT_TELEMETRY_SYSTEM_CACHE": str(cache)}):
                with patch.object(device_observations.psutil, "cpu_percent") as legacy_cpu:
                    with patch.object(device_observations.psutil, "virtual_memory") as legacy_memory:
                        cpu = device_observations.get_cpu_info()
                        self.assertEqual(cpu["used_percent"], 0)
                        self.assertIsNone(cpu["temperature_c"])
                        self.assertEqual(cpu["source"], "piagent_telemetry")
                        self.assertEqual(device_observations.get_memory_info()["used_percent"], 25)
                        cache.write_text('{"sampled_at_ms":"0"}', encoding="utf-8")
                        with self.assertRaises(device_observations.ObservationError):
                            device_observations.get_cpu_info()
                        legacy_cpu.assert_not_called()
                        legacy_memory.assert_not_called()
