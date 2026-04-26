# Ticket 036: Add EOS Connect Service

**Status**: IN_PROGRESS
**Created**: 2026-04-26
**Updated**: 2026-04-26

## Task

Add EOS Connect as the read-only orchestration and observation service between Akkudoktor-EOS, evcc, Home Assistant, and MQTT.

## Implementation Plan

1. Add `modules/services/eos-connect.nix`.
2. Run EOS Connect as an OCI container, following the existing containerized service pattern.
3. Use `ghcr.io/ohand/eos_connect` with a configurable `image` option so the implementation can pin a tag or digest.
4. Persist EOS Connect data/config under `/var/lib/eos-connect`.
5. Expose EOS Connect through Caddy at `https://eos-connect.frame1.hobitin.eu` and add a Homepage entry if the service exposes a UI.
6. Wire EOS Connect to:
   - Akkudoktor-EOS at the local EOS API endpoint
   - evcc at the local evcc API endpoint for state reads only
   - Home Assistant at the local Home Assistant endpoint for state/history reads only
   - Mosquitto for telemetry, state sharing, and selected override topics
7. Extend secrets as needed:
   - Home Assistant long-lived access token or equivalent API credential, read-only or least-privilege if supported
   - dedicated EOS Connect MQTT password
   - optional evcc credential if evcc API authentication is enabled later
8. Extend the Mosquitto module with a dedicated `eos-connect` MQTT user, password-file option, and narrowly scoped ACLs.
9. Define command ownership in docs:
   - EOS Connect must not command evcc during the first rollout.
   - EOS Connect must not call Home Assistant services during the first rollout.
   - MQTT is not the sole command path and must not create competing control loops.
10. Configure EOS Connect in dry-run, advisory, simulation, or equivalent no-actuation mode if upstream supports it.
11. If upstream cannot enforce no-actuation mode, omit write-capable credentials and document the missing active-control wiring.

Control boundary:

- EOS Connect may compute and publish advisory plans, but must not convert optimization results into commands during the first rollout.
- Home Assistant automations may provide existing local behavior and manual overrides, but should not duplicate future EOS Connect active control logic.
- MQTT topics should be used for state, diagnostics, dashboards, and explicit override signals.
- MQTT command topics must not be subscribed by active automations in the first rollout.

## Work Log

### 2026-04-26

- Created ticket from the hybrid integration decision in Ticket 033.
- Chose EOS Connect instead of custom glue so the stack remains based on existing upstream components.
- Chose dedicated MQTT identity and HA API credential handling for EOS Connect.
- Marked the first EOS Connect rollout as read-only/advisory.
- Deferred evcc commands, Home Assistant service calls, and MQTT command subscriptions to a later active-control ticket.
- Added `modules/services/eos-connect.nix` as an OCI container module.
- Configured EOS Connect with persistent `/app/data`, a generated `/etc/eos-connect/config.yaml`, host networking, and Caddy routing at `https://eos-connect.frame1.hobitin.eu`.
- Added the `eos-connect` Mosquitto user with read access to existing telemetry topics and write access only under `eos-connect/#`.
- Added `secrets/mqtt-eos-connect-password.age` wiring through agenix.
- Documented the service in `docs/services/eos-connect.md`.
- Checked GHCR tags and used `ghcr.io/ohand/eos_connect:latest`; the `snapshot` tag from the upstream compose file was not published.

## Validation Notes

Planned validation:

- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
- `./scripts/run-vm-docker.sh --build`
- Runtime check after deploy:
  - `systemctl status podman-eos-connect`
  - `journalctl -u podman-eos-connect -n 200 --no-pager`
  - verify EOS Connect can reach EOS, evcc, Home Assistant, and Mosquitto
