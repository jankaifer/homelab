# Ticket 034: Add evcc Service

**Status**: PLANNING
**Created**: 2026-04-26
**Updated**: 2026-04-26

## Task

Add evcc as the authoritative EV charging and loadpoint control service for the homelab energy stack.

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

Control boundary:

- evcc owns EV charging and loadpoint behavior.
- Home Assistant must not be configured as a competing controller for evcc.
- EOS Connect may command evcc through evcc's API or explicitly supported control interface.
- MQTT from evcc is primarily for state propagation and observability.

## Work Log

### 2026-04-26

- Created ticket from the hybrid integration decision in Ticket 033.
- Chose a dedicated evcc MQTT identity instead of reusing the existing Home Assistant MQTT user.

## Validation Notes

Planned validation:

- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
- `./scripts/run-vm-docker.sh --build`
- Runtime check after deploy:
  - `systemctl status evcc`
  - `journalctl -u evcc -n 200 --no-pager`
  - open `https://evcc.frame1.hobitin.eu`
