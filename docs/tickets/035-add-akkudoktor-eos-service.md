# Ticket 035: Add Akkudoktor-EOS Service

**Status**: PLANNING
**Created**: 2026-04-26
**Updated**: 2026-04-26

## Task

Add Akkudoktor-EOS as the optimizer API service for the homelab energy stack.

## Implementation Plan

1. Add `modules/services/akkudoktor-eos.nix`.
2. Run EOS as an OCI container, following the existing Home Assistant and Zigbee2MQTT container pattern.
3. Use the upstream `akkudoktor/eos` image with a configurable `image` option so the implementation can pin a tag or digest.
4. Persist EOS data under `/var/lib/akkudoktor-eos`.
5. Expose the EOS API on an internal host-local port, expected to be `8503`.
6. Expose the EOS dashboard/UI on an internal host-local port, expected to be `8504`, if the upstream image provides it.
7. Route EOS through Caddy at `https://eos.frame1.hobitin.eu` and add a Homepage entry.
8. Keep EOS as a pure optimizer service:
   - no direct charger control
   - no direct heat pump control
   - no direct MQTT command publishing in v1
9. Document that EOS Connect is the only planned caller that turns optimizer output into control decisions.

Control boundary:

- EOS receives forecasts, prices, constraints, and current state from EOS Connect.
- EOS returns an optimization plan.
- EOS does not command evcc, Home Assistant, MQTT, or physical devices directly.

## Work Log

### 2026-04-26

- Created ticket from the hybrid integration decision in Ticket 033.
- Confirmed EOS belongs in the stack as an optimizer API, not as the orchestration layer.

## Validation Notes

Planned validation:

- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
- `./scripts/run-vm-docker.sh --build`
- Runtime check after deploy:
  - `systemctl status podman-akkudoktor-eos`
  - `journalctl -u podman-akkudoktor-eos -n 200 --no-pager`
  - open `https://eos.frame1.hobitin.eu`
  - verify EOS API health/version endpoint if provided by upstream
