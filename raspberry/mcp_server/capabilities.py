"""PocketNet MCP capability domains and planned tool descriptions."""

from enum import StrEnum


class CapabilityStatus(StrEnum):
    AVAILABLE = "AVAILABLE"
    UNAVAILABLE = "UNAVAILABLE"
    DEGRADED = "DEGRADED"
    ERROR = "ERROR"


PLANNED_TOOLS = {
    "wireless_discovery": {
        "scan_wireless_environment": "Request a survey of the nearby wireless environment.",
        "get_access_points": "List observed access points and their radio metadata.",
        "get_ap_details": "Read observations for a selected access point.",
        "get_wireless_clients": "List wirelessly observed clients.",
        "get_wifi_channels": "Summarize observed wireless channels.",
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
        "analyze_packet_capture": "Summarize a selected packet capture.",
        "analyze_protocol_distribution": "Summarize protocol counts in a packet capture.",
        "analyze_dns_behavior": "Summarize DNS observations in a packet capture.",
    },
    "security_analysis": {
        "get_security_events": "List recorded network security observations.",
        "detect_rogue_ap_candidates": "Review observed access points for rogue AP candidates.",
        "detect_arp_anomalies": "Review ARP observations for anomalies.",
        "detect_ip_conflicts": "Review observations for conflicting IP assignments.",
        "audit_wireless_security": "Review observed wireless security properties.",
    },
    "network_diagnosis": {
        "diagnose_network": "Summarize available observations for a network diagnosis.",
        "investigate_network_event": "Review observations related to a selected network event.",
        "investigate_device": "Review available network observations for a selected device.",
        "generate_diagnosis_report": "Generate a report from an existing diagnosis.",
    },
}

PLANNED_MUTATING_TOOLS = {
    "start_wireless_monitoring",
    "stop_wireless_monitoring",
    "generate_diagnosis_report",
}
