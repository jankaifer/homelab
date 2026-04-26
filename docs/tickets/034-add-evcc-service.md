# Ticket 034: Add evcc Service

**Status**: PLANNING
**Created**: 2026-04-26
**Updated**: 2026-04-26

## Task

Add evcc as the EV charging and loadpoint service for the homelab energy stack, initially in read-only/commissioning mode.

## Implementation Plan

1. Add `modules/services/evcc.nix` as a homelab wrapper around the upstream NixOS `services.evcc` module.
2. Import and enable it from `machines/frame1/default.nix`.
3. Expose evcc through Caddy at `https://evcc.frame1.hobitin.eu` and add a Homepage entry.
4. Bind the evcc UI/API to a host-local port, expected to be `7070`, and keep it behind Caddy rather than opening it directly on the firewall.
5. Configure only runnable platform defaults in Nix:
   - service enablement
   - HTTP listen address/port
   - MQTT integration to the local Mosquitto broker
   - persistent state/config path
6. Extend the Mosquitto module with a dedicated `evcc` MQTT user, password-file option, and ACLs for `evcc/#`.
7. Add an agenix secret placeholder/wiring for the evcc MQTT password.
8. Leave real charger, meter, inverter, tariff, and vehicle setup to evcc commissioning after deployment.
9. For the first rollout, run evcc in a no-actuation mode:
   - no real charger configured
   - no real loadpoint configured with a write-capable charger
   - no wallbox API credentials
   - no OCPP endpoint accepted from a real charger
   - no vehicle API credentials that can change charging behavior
10. Use evcc demo/offline/simulated configuration if a loadpoint is required to make the UI useful.
11. Allow real meter or vehicle state reads only if the integration can be configured without write capability.
12. Publish evcc state to MQTT if available, but do not wire MQTT topics that can command charging behavior.

Control boundary:

- evcc owns EV charging and loadpoint behavior.
- Home Assistant must not be configured as a competing controller for evcc.
- EOS Connect must not command evcc in the first rollout.
- A later active-control ticket may allow EOS Connect to command evcc through evcc's API or explicitly supported control interface.
- MQTT from evcc is primarily for state propagation and observability.
- The first rollout must not let evcc start, stop, throttle, or otherwise influence real vehicle charging.

## Work Log

### 2026-04-26

- Created ticket from the hybrid integration decision in Ticket 033.
- Chose a dedicated evcc MQTT identity instead of reusing the existing Home Assistant MQTT user.
- Marked the first evcc rollout as read-only/commissioning mode.
- Deferred charger control and command-capable MQTT wiring to a later active-control phase.
- Made the evcc no-actuation requirement explicit: no real charger/loadpoint write path in the first rollout.
- Allowed only demo/offline/simulated evcc behavior, plus real read-only telemetry where feasible.

## Validation Notes

Planned validation:

- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
- `./scripts/run-vm-docker.sh --build`
- Runtime check after deploy:
  - `systemctl status evcc`
  - `journalctl -u evcc -n 200 --no-pager`
  - open `https://evcc.frame1.hobitin.eu`
