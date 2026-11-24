# PocketNet

PocketNet is a Raspberry Pi based passive wireless security observation device.

## V2 architecture

- Raspberry Pi built-in Wi-Fi provides the private phone management hotspot.
- A separately bound USB Wi-Fi adapter operates in Monitor Mode.
- Kismet tracks wireless state in RAM. The managed USB adapter starts in the light profile and can switch to balanced or extended. Capture files are disabled by default.
- A native C++ service sends system metrics, wireless summaries, recent events, and bounded device pages over TLS gRPC. A local allowlisted service handles recovery and capture profile changes.
- The Flutter app provides a live dashboard, normal monitoring, and a high-risk archive. Ordinary observations remain in RAM. High-risk deliveries use a bounded queue on the Pi for up to 180 seconds and are acknowledged after the phone commits them to SQLite.
- BLE enrollment, BLE time synchronization and the small USB/Kismet datasource manager remain Python components for now. Ubuntu 22.04 deployment must provide Python 3.12 for the BLE time-sync service.
- There is no MCP server, MCP SDK, or Agent runtime on the Raspberry Pi. The business interface is gRPC/Protobuf.
- The mobile navigation reserves the deep inspection and active testing pages for future releases.

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

See the [Ubuntu 22.04 ARM64 image builder](docs/image-builder.md) for building a development image, configuring wired SSH at `192.168.77.2`, and installing software updates.

See [V2 monitoring and acceptance](docs/v2-monitoring.md) for the current runtime, upgrade and rollback behavior. [V1 telemetry](docs/v1.0-telemetry.md) and the [wireless manager](docs/v1.0-wireless-manager.md) document the earlier release.
