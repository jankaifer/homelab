# Ticket 012: Podman Runtime Foundation for Smart-Home Services

**Status**: IN_PROGRESS
**Created**: 2026-02-08
**Updated**: 2026-02-08

## Task

Enable Podman + OCI runtime baseline for smart-home services on `frame1` and define runtime conventions for containerized services.

## Implementation Plan

1. Enable Podman and OCI container backend in machine config
2. Define pinned image and restart conventions in service modules
3. Reserve smart-home hostname namespace:
   - `home.frame1.hobitin.eu`
   - `zigbee.frame1.hobitin.eu`
   - `mqtt.frame1.hobitin.eu`
4. Update docs with runtime model and hostnames

## Work Log

### 2026-02-08

- Enabled `virtualisation.podman` and `virtualisation.oci-containers.backend = "podman"` in `machines/frame1/default.nix`
- Established container conventions in new modules:
  - Pinned image tags
  - Persistent volumes under `/var/lib/...`
  - Systemd restart behavior (`Restart=always`)
- Reserved hostname defaults in module options for Home Assistant, Zigbee2MQTT, and MQTT

## Validation Notes

- Pending: `nix eval` and VM build checks
- Pending: verify existing services unaffected after deployment
