# Ticket 015: Add Home Assistant Core Module (Podman, Host Networking)

**Status**: IN_PROGRESS
**Created**: 2026-02-08
**Updated**: 2026-02-08

## Task

Add Home Assistant Core as a Podman-managed OCI container using host networking for maximum discovery compatibility, routed through Caddy.

## Implementation Plan

1. Create `modules/services/homeassistant.nix`
2. Run Home Assistant Core container with:
   - Pinned image
   - Persistent `/config` storage
   - Host networking
3. Add Caddy route for `home.frame1.hobitin.eu`
4. Register service in Homepage dashboard
5. Add service documentation

## Work Log

### 2026-02-08

- Created `modules/services/homeassistant.nix` with `homelab.services.homeassistant.*` options
- Added containerized Home Assistant Core with `--network=host`
- Added persistent data dir setup via tmpfiles
- Added Caddy reverse proxy integration and Homepage registration

## Validation Notes

- Pending runtime checks:
  - Home Assistant reachability via `home.frame1.hobitin.eu`
  - MQTT integration over TLS to Mosquitto
  - Discovery flow with Zigbee2MQTT topics/entities
