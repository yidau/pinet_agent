"""Names, domains and descriptions for the PocketNet network tool catalog."""

from enum import StrEnum


class CapabilityStatus(StrEnum):
    AVAILABLE = "AVAILABLE"
    UNAVAILABLE = "UNAVAILABLE"
    DEGRADED = "DEGRADED"
    ERROR = "ERROR"


NETWORK_TOOLS = {
    "kismet": {
        "get_kismet_status": "Read the local Kismet server's current operational status.",
        "get_kismet_version": "Read the software version reported by the local Kismet REST API.",
        "get_kismet_datasources": "List configured Kismet data sources and their current state.",
        "get_kismet_datasource_status": "Read managed Wi-Fi scan, monitor, Bluetooth active scan and offline replay status and reasons.",
        "get_kismet_devices": "Read a bounded list of device observations already recorded by Kismet.",
        "get_kismet_alerts": "Read recent alerts already recorded by Kismet.",
        "get_kismet_capture_status": "Report the current state of Kismet's capture sources.",
    },
    "wireless_discovery": {
        "scan_wireless_environment": "Read an existing Wi-Fi observation summary. This query does not start a radio scan.",
        "get_access_points": "List observed access points and their radio metadata.",
        "get_ap_details": "Read observations for a selected access point.",
        "get_wireless_clients": "List wirelessly observed clients.",
        "get_wifi_channels": "Summarize observed wireless channels.",
    },
    "bluetooth": {
        "get_bluetooth_devices": "List Bluetooth devices observed by an active Linux Bluetooth source.",
        "get_bluetooth_device_details": "Read a Bluetooth observation by its returned device id.",
    },
    "wireless_monitoring": {
        "start_wireless_monitoring": "Start a wireless observation session.",
        "stop_wireless_monitoring": "Stop a wireless observation session.",
        "get_signal_history": "Read recorded wireless signal measurements over time.",
        "get_wireless_events": "List events observed during wireless monitoring.",
    },
    "network_discovery": {
        "get_network_profile": "Read the device's current local network profile.",
        "get_network_interfaces": "List network interfaces and their assigned addresses.",
        "get_arp_neighbors": "Read the observed ARP neighbor table.",
        "get_routes": "List network routes visible to the device.",
        "discover_lan_devices": "List devices discovered on the local network.",
    },
    "packet_analysis": {
        "list_captures": "List recorded packet capture files.",
        "get_capture_metadata": "Read the metadata of a selected packet capture.",
        "replay_capture": "Start bounded, offline file replay for a selected capture after explicit operator authorization.",
        "get_capture_status": "Read the state and source of offline file replay.",
        "stop_capture_replay": "Stop the current offline file replay after explicit operator authorization.",
        "analyze_packet_capture": "Summarize a selected packet capture.",
        "analyze_protocol_distribution": "Summarize protocol counts in a packet capture.",
        "analyze_dns_behavior": "Summarize DNS observations in a packet capture.",
        "list_wireless_captures": "List recorded wireless packet capture files.",
        "get_packet_statistics": "Read statistics from a wireless packet capture.",
        "get_protocol_distribution": "Read the observed protocol distribution from a packet capture.",
    },
    "security_analysis": {
        "get_security_events": "List recorded network security observations.",
        "detect_rogue_ap_candidates": "Review observed access points for rogue AP candidates.",
        "detect_arp_anomalies": "Review ARP observations for anomalies.",
        "detect_ip_conflicts": "Review observations for conflicting IP assignments.",
        "audit_wireless_security": "Review observed wireless security properties.",
        "get_wireless_security_events": "List recorded wireless security observations.",
        "detect_ap_security_changes": "Identify changes in the recorded security properties of an access point.",
        "investigate_wireless_anomaly": "Review observations related to a wireless anomaly.",
    },
    "network_diagnosis": {
        "diagnose_network": "Summarize available observations for a network diagnosis.",
        "investigate_network_event": "Review observations related to a selected network event.",
        "investigate_device": "Review available network observations for a selected device.",
        "generate_diagnosis_report": "Generate a report from an existing diagnosis.",
    },
}

MUTATING_TOOLS = {
    "replay_capture",
    "stop_capture_replay",
    "start_wireless_monitoring",
    "stop_wireless_monitoring",
    "generate_diagnosis_report",
}
