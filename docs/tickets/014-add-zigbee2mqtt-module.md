# Ticket 014: Add Zigbee2MQTT Module (Podman, USB Sonoff)

**Status**: IN_PROGRESS
**Created**: 2026-02-08
**Updated**: 2026-03-26

## Task

Add Zigbee2MQTT as a Podman-managed OCI container with direct USB coordinator access, MQTT TLS integration, and Caddy-routed UI endpoint.

## Implementation Plan

1. Create `modules/services/zigbee2mqtt.nix`
2. Add container config:
   - Pinned image
   - Persistent data dir
   - USB pass-through via `/dev/serial/by-id/...`
3. Generate `configuration.yaml` from Nix options at startup
4. Configure MQTT over TLS against Mosquitto
5. Add Caddy route for `zigbee.frame1.hobitin.eu`
6. Add service documentation

## Work Log

### 2026-02-08

- Created `modules/services/zigbee2mqtt.nix` with `homelab.services.zigbee2mqtt.*` options
- Added one-shot `zigbee2mqtt-config` unit to render runtime `configuration.yaml` with secret-backed MQTT password
- Added container definition under `virtualisation.oci-containers.containers.zigbee2mqtt`
- Added USB device mapping from configurable serial path
- Added TLS MQTT settings (`mqtts://`, CA file)
- Added Caddy reverse proxy integration and Homepage registration

### 2026-03-26

- Queried `frame1` over SSH and replaced the production Zigbee serial placeholder with the stable Sonoff by-id path:
  - `/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_20231101183952-if00`
- The production eval guardrail added earlier is now satisfied on `frame1`

## Validation Notes

- Pending runtime checks:
  - Coordinator detection via configured serial path
  - Successful MQTT TLS connection
  - UI reachability via `zigbee.frame1.hobitin.eu`
