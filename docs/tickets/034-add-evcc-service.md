# Ticket 034: Add evcc Service

**Status**: DONE
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
- Added `modules/services/evcc.nix` as a homelab wrapper around upstream `services.evcc`.
- Imported and enabled evcc on `frame1` at `https://evcc.frame1.hobitin.eu`.
- Added Caddy and Homepage registration for evcc.
- Configured evcc in demo mode with MQTT publishing to the local Mosquitto loopback listener.
- Added a dedicated `evcc` Mosquitto user, scoped ACLs for `evcc/#`, and Home Assistant read access to `evcc/#`.
- Added `secrets/mqtt-evcc-password.age` through agenix via Nix and documented the secret.
- Added a runtime `evcc-mqtt-env` preparation unit so the MQTT password is substituted without entering the Nix store.
- Confirmed evcc's `network.host` is advertised identity only; evcc listens on all interfaces by design, so the wrapper applies systemd loopback-only IP filtering during commissioning.
- Switched production evcc out of demo mode for real Victron GX grid, PV, and battery telemetry.
- Allowed evcc to reach only `192.168.2.31/32` in addition to localhost through systemd IP filtering.
- Kept the loadpoint non-actuating with a disabled demo charger placeholder because the Victron EVCS charger probe through GX Modbus returned gateway path unavailable.

## Validation Notes

Validation completed:

- `nix fmt`
- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
- `./scripts/run-vm-docker.sh --build`
- Booted VM with `./scripts/run-vm-docker.sh`
- Verified in the VM:
  - `mosquitto.service` active
  - `evcc-mqtt-env.service` completed successfully
  - `evcc.service` active with `--demo`
  - evcc route returns `HTTP/2 200` through Caddy at `https://evcc.frame1.hobitin.eu:8443`
  - `evcc.service` has `IPAddressDeny=any` and `IPAddressAllow=localhost`
- Verified in production after Victron integration:
  - evcc runs without `--demo`
  - `evcc.service` active
  - `IPAddressAllow` includes localhost and `192.168.2.31/32`
  - logs show `meters: grid ✓ pv ✓ battery ✓`
  - logs show live Victron grid, PV, battery power, and battery SOC readings
  - `https://evcc.frame1.hobitin.eu` returns HTTP 200
- Added `secrets/evcc-admin-password.age` and `evcc-admin-password.service` to apply the UI admin password from agenix with `evcc password set`.
- Renamed the placeholder vehicle to `Tesla Model 3`, added `secrets/evcc-tesla.env.age` to the agenix rules, made the evcc wrapper able to append extra runtime secret env files, and made frame1 automatically switch that vehicle to the Tesla API template once the encrypted env secret exists.
- Added the Tesla API credentials secret for the Model 3 and relaxed EVCC's systemd IP filter on frame1 so it can reach Tesla cloud APIs while the charger path remains non-actuating.
