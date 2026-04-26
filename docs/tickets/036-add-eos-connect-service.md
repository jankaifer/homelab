# Ticket 036: Add EOS Connect Service

**Status**: PLANNING
**Created**: 2026-04-26
**Updated**: 2026-04-26

## Task

Add EOS Connect as the orchestration service between Akkudoktor-EOS, evcc, Home Assistant, and MQTT.

## Implementation Plan

1. Add `modules/services/eos-connect.nix`.
2. Run EOS Connect as an OCI container, following the existing containerized service pattern.
3. Use `ghcr.io/ohand/eos_connect` with a configurable `image` option so the implementation can pin a tag or digest.
4. Persist EOS Connect data/config under `/var/lib/eos-connect`.
5. Expose EOS Connect through Caddy at `https://eos-connect.frame1.hobitin.eu` and add a Homepage entry if the service exposes a UI.
6. Wire EOS Connect to:
   - Akkudoktor-EOS at the local EOS API endpoint
   - evcc at the local evcc API endpoint
   - Home Assistant at the local Home Assistant endpoint
   - Mosquitto for telemetry, state sharing, and selected override topics
7. Extend secrets as needed:
   - Home Assistant long-lived access token or equivalent API credential
   - dedicated EOS Connect MQTT password
   - optional evcc credential if evcc API authentication is enabled later
8. Extend the Mosquitto module with a dedicated `eos-connect` MQTT user, password-file option, and narrowly scoped ACLs.
9. Define command ownership in docs:
   - EOS Connect may command evcc for EV charging decisions.
   - EOS Connect may command Home Assistant for heat pump and household device decisions.
   - MQTT is not the sole command path and must not create competing control loops.

Control boundary:

- EOS Connect is the only orchestration service that converts optimization results into commands.
- Home Assistant automations may provide local fallbacks and manual overrides, but should not duplicate EOS Connect's active control logic.
- MQTT topics should be used for state, diagnostics, dashboards, and explicit override signals.

## Work Log

### 2026-04-26

- Created ticket from the hybrid integration decision in Ticket 033.
- Chose EOS Connect instead of custom glue so the stack remains based on existing upstream components.
- Chose dedicated MQTT identity and HA API credential handling for EOS Connect.

## Validation Notes

Planned validation:

- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
- `./scripts/run-vm-docker.sh --build`
- Runtime check after deploy:
  - `systemctl status podman-eos-connect`
  - `journalctl -u podman-eos-connect -n 200 --no-pager`
  - verify EOS Connect can reach EOS, evcc, Home Assistant, and Mosquitto
