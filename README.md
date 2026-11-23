# PocketNet

PocketNet is a Raspberry Pi based passive wireless security observation device.

## V1 architecture

- Raspberry Pi built-in Wi-Fi provides the private phone management hotspot.
- A separately bound USB Wi-Fi adapter operates in Monitor Mode.
- Kismet is the persistent wireless capture engine. The managed Linux Wi-Fi source uses `filter_mgmt=true` to retain management frames and EAPOL.
- A native C++ service collects Linux metrics, reads Kismet metadata, stores bounded security events, and exposes a TLS gRPC/Protobuf streaming API.
- The Flutter app provides the live dashboard and SQLite-backed event center.
- BLE enrollment, BLE time synchronization and the small USB/Kismet datasource manager remain Python components for now. Ubuntu 22.04 deployment must provide Python 3.12 for the BLE time-sync service.
- There is no MCP server, MCP SDK, or Agent runtime on the Raspberry Pi. The business interface is gRPC/Protobuf.
- AI is reserved in the mobile UI and is not implemented in this release.

## Repository layout

- `raspberry/telemetry`: C++ collectors, event store, gRPC service and Protobuf schema.
- `raspberry/wireless`: the small Python USB-radio/Kismet datasource manager and bounded Kismet REST adapter.
- `raspberry/enrollment`: BLE phone enrollment and device authorization.
- `raspberry/time_sync`: BLE time synchronization.
- `raspberry/config`: systemd units and provisioning scripts.
- `mobile`: Flutter dashboard, message center, BLE enrollment and gRPC client.

## Enrollment contract

The permanent QR identifies the Pi and authorizes BLE enrollment. The BLE response returns the hotspot credentials, the TLS CA certificate, a per-phone token, and a gRPC telemetry endpoint of the form:

`https://<management-hotspot-address>:9443`

The phone connects to the C++ gRPC service using the pinned CA and its per-device bearer token. No HTTP MCP endpoint is created.

## Current deployment status

The source tree contains the application and service definitions. A complete Ubuntu 22.04 ARM64 offline image builder is a separate packaging task; do not assume the current repository automatically creates a flashable image.

See [V1 telemetry](docs/v1.0-telemetry.md) and [wireless manager](docs/v1.0-wireless-manager.md) for runtime details.
