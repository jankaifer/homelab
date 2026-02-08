# Ticket 016: Smart-Home Integration, Hardening, and Validation

**Status**: IN_PROGRESS
**Created**: 2026-02-08
**Updated**: 2026-02-08

## Task

Integrate Mosquitto, Zigbee2MQTT, and Home Assistant on `frame1`, wire required secrets, update documentation, and define smoke-check runbook steps.

## Implementation Plan

1. Import and enable new modules in `machines/frame1/default.nix`
2. Add secret declarations in `secrets/secrets.nix`
3. Add encrypted placeholder secret files for MQTT passwords
4. Update overview and service documentation
5. Run validation checks:
   - Nix eval
   - VM build
   - frame1 smoke checks

## Work Log

### 2026-02-08

- Imported and enabled:
  - `modules/services/mosquitto.nix`
  - `modules/services/zigbee2mqtt.nix`
  - `modules/services/homeassistant.nix`
- Added `age.secrets` declarations in machine config for MQTT client passwords
- Added secret policy entries in `secrets/secrets.nix`
- Added encrypted placeholder files:
  - `secrets/mqtt-homeassistant-password.age`
  - `secrets/mqtt-zigbee2mqtt-password.age`
- Updated Cloudflare token example to include `CLOUDFLARE_DNS_API_TOKEN` for NixOS ACME lego provider

## Smoke-Check Runbook

1. Validate and build:
   - `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
   - `./scripts/run-vm-docker.sh --build`
2. Deploy:
   - `nix run .#deploy -- .#frame1 --skip-checks`
3. MQTT checks on frame1:
   - `mosquitto_sub -h mqtt.frame1.hobitin.eu -p 8883 --cafile /var/lib/acme/mqtt.frame1.hobitin.eu/fullchain.pem -u zigbee2mqtt -P "$(cat /run/agenix/mqtt-zigbee2mqtt-password)" -t 'zigbee2mqtt/#' -v`
   - Verify invalid password is rejected
4. Zigbee adapter check:
   - `ls -l /dev/serial/by-id/`
   - `journalctl -u podman-zigbee2mqtt -n 200 --no-pager`
5. HA flow:
   - Open `https://home.frame1.hobitin.eu`
   - Configure MQTT integration with TLS/CA and `homeassistant` credentials
   - Verify Zigbee2MQTT discovery entities appear
