"""Offline wireless-role fixtures. No radio, systemd, or packet capture is needed."""

from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from raspberry.mcp_server import wireless_manager as radio
from raspberry.mcp_server.kismet_adapter import KismetError
from raspberry.mcp_server.managed_scan import ScanUnavailable, check_monitor_reservation, check_scan_radio


UUID = "11111111-2222-3333-4444-555555555555"
CONFIG = radio.MonitorConfig("1234", "4567", "1-1.2", "usb_driver", UUID, 2501)
USB = radio.UsbRadio(Path("phy2"), "1-1.2", "1234", "4567", "usb_driver", 7)
DEV = "phy#2\n\tInterface pn-wifi0\n\t\ttype managed\nphy#0\n\tInterface wlan0\n\t\ttype AP\n"
PHY = "Wiphy phy2\n\tSupported interface modes:\n\t\t * managed\n\t\t * monitor\n\tBand 1:\n"


def kismet_source(*, running=True, uuid=UUID):
    fields = {"uuid": uuid.upper(), "name": radio.SOURCE_NAME, "remote": 0, "retry": 0,
              "interface": radio.MONITOR_INTERFACE, "capture_interface": radio.MONITOR_VIF,
              "definition": f"{radio.MONITOR_INTERFACE}:type=linuxwifi,vif={radio.MONITOR_VIF}",
              "running": running, "paused": 0, "error": 0,
              "type_driver": {"kismet.datasource.driver.type": "linuxwifi"}}
    return {radio.FIELD + key: value for key, value in fields.items()}


class WirelessRoleTests(unittest.TestCase):
    def setUp(self):
        temporary = self.enterContext(tempfile.TemporaryDirectory())
        self.root = Path(temporary)
        self.hotspot = self.root / "hostapd.conf"
        self.hotspot.write_text("interface=wlan0\n", encoding="ascii")
        self.ap_phy = self.root / "wlan0" / "phy80211"
        self.ap_phy.mkdir(parents=True)

    def select(self, target=USB, output=(DEV, PHY)):
        query = Mock(side_effect=output)
        with patch.object(radio, "usb_radio", return_value=target):
            return radio.select_radio(CONFIG, self.root, self.hotspot, query)

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

    def test_managed_scan_cannot_use_the_monitor_radio_or_its_reserved_usb_port(self):
        def interface(index, kind, phy, name):
            row = Mock()
            row.get_attr.side_effect = {"NL80211_ATTR_IFINDEX": index, "NL80211_ATTR_IFTYPE": kind,
                                        "NL80211_ATTR_WIPHY": phy, "NL80211_ATTR_IFNAME": name}.get
            return row

        builtin = interface(1, 3, 0, "wlan0")
        usb_station = interface(2, 2, 1, "wlan1")
        for other in (interface(3, 6, 1, "monitor"), interface(3, 2, 1, radio.MONITOR_INTERFACE)):
            inventory = [builtin, usb_station, other]
            for shared_allowed, strict in ((True, False), (False, True)):
                with self.assertRaisesRegex(ScanUnavailable, "reserved for passive monitoring"):
                    check_scan_radio(inventory, 2, shared_allowed, strict)
            self.assertEqual(check_scan_radio(inventory, 1, True, False), 0)

        port_file = self.root / "assigned-port"
        port_file.write_text(CONFIG.port + "\n", encoding="ascii")
        usb = self.root / "usb"
        reserved_phy = usb / CONFIG.port / "usb-interface" / "ieee80211"
        (reserved_phy / "phy1" / "device").mkdir(parents=True)
        builtin_phy = self.root / "onboard" / "ieee80211"
        (builtin_phy / "phy0" / "device").mkdir(parents=True)
        with self.assertRaisesRegex(ScanUnavailable, "USB radio is assigned"):
            check_monitor_reservation(1, port_file, usb, reserved_phy)
        check_monitor_reservation(0, port_file, usb, builtin_phy)


if __name__ == "__main__":
    unittest.main()
