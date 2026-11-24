"""Offline wireless-role fixtures. No radio, systemd, or packet capture is needed."""

from pathlib import Path
from dataclasses import replace
import tempfile
import unittest
from unittest.mock import Mock, patch

from raspberry.wireless import wireless_manager as radio
from raspberry.wireless.kismet_adapter import KismetError


UUID = "11111111-2222-3333-4444-555555555555"
CONFIG = radio.MonitorConfig("1234", "4567", "1-1.2", "usb_driver", UUID, 2501)
USB = radio.UsbRadio(Path("phy2"), "1-1.2", "1234", "4567", "usb_driver", 7)
DEV = "phy#2\n\tInterface pn-wifi0\n\t\ttype managed\nphy#0\n\tInterface wlan0\n\t\ttype AP\n"
PHY = "Wiphy phy2\n\tSupported interface modes:\n\t\t * managed\n\t\t * monitor\n\tBand 1:\n"


def kismet_source(*, running=True, uuid=UUID):
    fields = {"uuid": uuid.upper(), "name": radio.SOURCE_NAME, "remote": 0, "retry": 0,
              "interface": radio.MONITOR_INTERFACE, "capture_interface": radio.MONITOR_VIF,
              "definition": f"{radio.MONITOR_INTERFACE}:type=linuxwifi,vif={radio.MONITOR_VIF},filter_mgmt=true",
              "running": running, "paused": 0, "error": 0,
              "type_driver": {"kismet.datasource.driver.type": "linuxwifi"}}
    return {radio.FIELD + key: value for key, value in fields.items()}


class WirelessRoleTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.hotspot = self.root / "hostapd.conf"
        self.hotspot.write_text("interface=wlan0\n", encoding="ascii")
        self.ap_phy = self.root / "wlan0" / "phy80211"
        self.ap_phy.mkdir(parents=True)

    def select(self, target=USB, output=(DEV, PHY)):
        query = Mock(side_effect=output)
        with patch.object(radio, "usb_radio", return_value=target):
            return radio.select_radio(CONFIG, self.root, self.hotspot, query)

    def test_profile_requires_matching_definition_and_does_not_reopen_old_definition(self):
        definition = radio.FIELD + "definition"
        manager, api, _, _, source = self.running_manager()
        manager.profile = "balanced"
        self.assertEqual(manager.check(), ("degraded", "monitor_profile_not_applied", None))
        api.open_source.assert_not_called()
        api.close_source.assert_not_called()
        source[definition] = source[definition].replace("filter_mgmt=true",
            "filter_mgmt=false,truncate_data=true")
        self.assertEqual(radio.actual_profile(source), "balanced")
        self.assertEqual(manager.check(), ("ready", "", UUID))
        source[definition] += ",truncate_data=false"
        self.assertIsNone(radio.actual_profile(source))

    def running_manager(self, **fields):
        phy = self.root / "radios" / "phy2"
        phy.mkdir(parents=True)
        vif = self.root / radio.MONITOR_VIF
        vif.mkdir()
        (vif / "phy80211").symlink_to(phy, target_is_directory=True)
        current = replace(USB, phy=phy)
        detect = Mock(return_value=current)
        now = [10.0]
        source = kismet_source()
        source.update({radio.FIELD + key: value for key, value in fields.items()})
        api = Mock(list_sources=Mock(return_value=[source]))

        def stop(_):
            source[radio.FIELD + "running"] = False

        def start(_):
            source.update({radio.FIELD + "running": True, radio.FIELD + "error": False,
                           radio.FIELD + "paused": False})

        api.close_source.side_effect = stop
        api.open_source.side_effect = start
        manager = radio.MonitorManager(CONFIG, api, detect=detect, net=self.root, clock=lambda: now[0])
        return manager, api, detect, now, source

    def test_monitor_selection_requires_confirmed_usb_driver_port_and_distinct_phy(self):
        self.assertEqual(self.select(), USB)
        other_device = radio.UsbRadio(USB.phy, "1-1.3", USB.vendor, USB.product, USB.driver, 8)
        with self.assertRaisesRegex(radio.Unavailable, "monitor_identity_mismatch"):
            self.select(other_device)
        same_ap = radio.UsbRadio(self.ap_phy.resolve(), USB.port, USB.vendor, USB.product, USB.driver, 9)
        with self.assertRaisesRegex(radio.Unavailable, "monitor_shares_hotspot"):
            self.select(same_ap)
        with self.assertRaisesRegex(radio.Unavailable, "monitor_radio_in_use"):
            self.select(output=(DEV.replace("type managed", "type AP"), PHY))
        with self.assertRaisesRegex(radio.Unavailable, "monitor_mode_unavailable"):
            self.select(output=(DEV, PHY.replace(" * monitor", " * station")))
        # A VIF owned by another physical radio may not be reused by Kismet.
        (self.root / radio.MONITOR_VIF / "phy80211").mkdir(parents=True)
        with self.assertRaisesRegex(radio.Unavailable, "monitor_vif_conflict"):
            self.select()

    def test_hotplug_targets_one_uuid_and_checks_identity_before_open(self):
        vif_phy = self.root / radio.MONITOR_VIF / "phy80211"
        vif_phy.mkdir(parents=True)
        current_usb = radio.UsbRadio(vif_phy.resolve(), USB.port, USB.vendor, USB.product, USB.driver, 7)
        detect = Mock(return_value=current_usb)
        api = Mock(list_sources=Mock(return_value=[]))
        manager = radio.MonitorManager(CONFIG, api, detect=detect, net=self.root, clock=lambda: 10)
        self.assertEqual(manager.check()[0], "starting")
        api.add.assert_called_once_with(UUID)
        self.assertEqual(manager.check(), ("degraded", "monitor_waiting_for_source", None))
        self.assertEqual(api.add.call_count, 1)
        api.list_sources.return_value = [kismet_source()]
        self.assertEqual(manager.check(), ("ready", "", UUID))

        detect.side_effect = radio.Unavailable("usb_monitor_missing")
        self.assertEqual(manager.check(), ("degraded", "usb_monitor_missing", None))
        api.close_source.assert_called_once_with(UUID)
        api.list_sources.return_value = [kismet_source(running=False)]
        detect.side_effect = None
        self.assertEqual(manager.check()[0], "starting")
        api.open_source.assert_called_once_with(UUID)

    def test_unowned_source_is_never_mutated_and_api_failure_is_degraded(self):
        source = kismet_source()
        source[radio.FIELD + "name"] = "Existing source"
        api = Mock(list_sources=Mock(return_value=[source]))
        manager = radio.MonitorManager(CONFIG, api, detect=Mock(return_value=USB), net=self.root)
        self.assertEqual(manager.check(), ("degraded", "monitor_uuid_conflict", None))
        api.add.assert_not_called()
        api.close_source.assert_not_called()
        api.open_source.assert_not_called()
        source[radio.FIELD + "name"] = radio.SOURCE_NAME
        source[radio.FIELD + "definition"] = source[radio.FIELD + "definition"].replace(radio.MONITOR_VIF, "wlan0")
        self.assertEqual(manager.check(), ("degraded", "monitor_uuid_conflict", None))
        api.close_source.assert_not_called()
        api.list_sources.side_effect = KismetError("KISMET_CONNECTION", "no server")
        self.assertEqual(manager.check(), ("degraded", "kismet_connection", None))

    def test_running_error_recovers_without_restarting_kismet(self):
        manager, api, _, _, _ = self.running_manager(error=True)
        self.assertEqual(manager.check()[0], "starting")
        api.close_source.assert_called_once_with(UUID)
        api.open_source.assert_called_once_with(UUID)
        api.add.assert_not_called()
        self.assertEqual(manager.check(), ("ready", "", UUID))

    def test_fast_replug_with_new_ifindex_reopens_apparently_healthy_source(self):
        manager, api, detect, _, _ = self.running_manager()
        self.assertEqual(manager.check(), ("ready", "", UUID))
        # Removal and reinsertion both happened between the five-second polls.
        detect.return_value = replace(detect.return_value, ifindex=19)
        self.assertEqual(manager.check()[0], "starting")
        api.close_source.assert_called_once_with(UUID)
        api.open_source.assert_called_once_with(UUID)
        self.assertEqual(manager.check(), ("ready", "", UUID))

    def test_fast_replug_with_new_phy_does_not_trust_recreated_capture_name(self):
        manager, api, detect, _, _ = self.running_manager()
        self.assertEqual(manager.check(), ("ready", "", UUID))
        new_phy = self.root / "radios" / "phy3"
        new_phy.mkdir()
        link = self.root / radio.MONITOR_VIF / "phy80211"
        link.unlink()
        link.symlink_to(new_phy, target_is_directory=True)
        detect.return_value = replace(detect.return_value, phy=new_phy, ifindex=19)
        self.assertEqual(manager.check()[0], "starting")
        api.close_source.assert_called_once_with(UUID)
        api.open_source.assert_called_once_with(UUID)

    def test_missing_old_capture_interface_is_reopened_in_same_recovery_attempt(self):
        manager, api, _, _, _ = self.running_manager()
        self.assertEqual(manager.check(), ("ready", "", UUID))
        (self.root / radio.MONITOR_VIF / "phy80211").unlink()
        self.assertEqual(manager.check()[0], "starting")
        api.close_source.assert_called_once_with(UUID)
        api.open_source.assert_called_once_with(UUID)

    def test_failed_close_remains_degraded_and_retries_with_backoff(self):
        manager, api, _, now, source = self.running_manager(error=True)
        stop = api.close_source.side_effect
        api.close_source.side_effect = KismetError("KISMET_CONNECTION", "close failed")
        self.assertEqual(manager.check(), ("degraded", "kismet_connection", None))
        api.open_source.assert_not_called()
        source[radio.FIELD + "error"] = False
        now[0] += radio.POLL_SECONDS
        self.assertEqual(manager.check(), ("degraded", "monitor_waiting_for_source", None))
        self.assertEqual(api.close_source.call_count, 1)
        api.close_source.side_effect = stop
        now[0] += radio.RETRY_SECONDS
        self.assertEqual(manager.check()[0], "starting")
        self.assertEqual(api.close_source.call_count, 2)
        self.assertEqual(manager.check(), ("ready", "", UUID))

    def test_failed_open_with_stale_running_flag_is_not_reported_as_ready(self):
        manager, api, _, now, _ = self.running_manager(error=True)
        start = api.open_source.side_effect

        def uncertain_open(uuid):
            start(uuid)
            raise KismetError("KISMET_CONNECTION", "open response timed out")

        api.open_source.side_effect = uncertain_open
        self.assertEqual(manager.check(), ("degraded", "kismet_connection", None))
        now[0] += radio.POLL_SECONDS
        self.assertEqual(manager.check(), ("degraded", "monitor_waiting_for_source", None))
        self.assertEqual(api.open_source.call_count, 1)
        api.open_source.side_effect = start
        now[0] += radio.RETRY_SECONDS
        self.assertEqual(manager.check()[0], "starting")
        self.assertEqual(api.open_source.call_count, 2)
        self.assertEqual(manager.check(), ("ready", "", UUID))

    def test_open_waits_until_close_is_observed_stopped(self):
        manager, api, _, now, _ = self.running_manager(error=True)
        stop = api.close_source.side_effect
        api.close_source.side_effect = None
        self.assertEqual(manager.check(), ("starting", "monitor_waiting_for_stop", None))
        api.open_source.assert_not_called()
        now[0] += radio.POLL_SECONDS
        self.assertEqual(manager.check()[0], "degraded")
        self.assertEqual(api.close_source.call_count, 1)
        api.close_source.side_effect = stop
        now[0] += radio.RETRY_SECONDS
        self.assertEqual(manager.check()[0], "starting")
        api.open_source.assert_called_once_with(UUID)

    def test_rechecks_physical_generation_and_ownership_after_close(self):
        manager, api, detect, _, source = self.running_manager(error=True)
        stop = api.close_source.side_effect

        def unplug_during_close(uuid):
            stop(uuid)
            detect.return_value = replace(detect.return_value, ifindex=19)

        api.close_source.side_effect = unplug_during_close
        self.assertEqual(manager.check(), ("degraded", "monitor_identity_changed", None))
        api.open_source.assert_not_called()
        # A different source taking the reserved UUID must still never be opened.
        source[radio.FIELD + "name"] = "Other source"
        self.assertEqual(manager.check(), ("degraded", "monitor_uuid_conflict", None))
        api.open_source.assert_not_called()
        api.add.assert_not_called()

    def test_unsafe_physical_identity_does_not_change_kismet_sources(self):
        manager, api, detect, _, _ = self.running_manager()
        for reason in ("monitor_shares_hotspot", "management_radio_unknown", "monitor_identity_mismatch"):
            with self.subTest(reason=reason):
                detect.side_effect = radio.Unavailable(reason)
                self.assertEqual(manager.check(), ("degraded", reason, None))
        api.close_source.assert_not_called()
        api.open_source.assert_not_called()
        api.add.assert_not_called()

    def test_uuid_taken_over_during_close_is_not_reopened(self):
        manager, api, _, _, source = self.running_manager(error=True)
        stop = api.close_source.side_effect

        def replaced_after_close(uuid):
            stop(uuid)
            source[radio.FIELD + "name"] = "Other source"

        api.close_source.side_effect = replaced_after_close
        self.assertEqual(manager.check(), ("degraded", "monitor_uuid_conflict", None))
        api.close_source.assert_called_once_with(UUID)
        api.open_source.assert_not_called()
        api.add.assert_not_called()

    def test_another_uuid_using_the_monitor_is_not_mutated(self):
        manager, api, _, _, source = self.running_manager()
        source[radio.FIELD + "uuid"] = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        self.assertEqual(manager.check(), ("degraded", "monitor_source_conflict", None))
        api.close_source.assert_not_called()
        api.open_source.assert_not_called()
        api.add.assert_not_called()

    def test_operator_pause_alone_does_not_trigger_a_reopen(self):
        manager, api, _, _, _ = self.running_manager(paused=True)
        self.assertEqual(manager.check(), ("degraded", "monitor_source_paused", None))
        api.close_source.assert_not_called()
        api.open_source.assert_not_called()

