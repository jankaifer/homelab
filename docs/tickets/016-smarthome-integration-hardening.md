# Ticket 016: Smart-Home Integration, Hardening, and Validation

**Status**: IN_PROGRESS
**Created**: 2026-02-08
**Updated**: 2026-03-27

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

### 2026-03-16

- Re-ran the validation gates successfully:
  - `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
  - `./scripts/run-vm-docker.sh --build`
- Added loopback hostname pinning for `mqtt.frame1.hobitin.eu` on `frame1` so host-local smart-home clients can reuse the broker TLS hostname without relying on external DNS or hairpin routing.
- Expanded VM DNS testing docs for the smart-home web entrypoints.
- Fixed the `frame1-vm` overlay so Caddy uses internal TLS during local testing instead of trying real Cloudflare/Let's Encrypt issuance.
- Removed the invalid `agenix.service` dependency from `zigbee2mqtt-config.service`; the config generator now runs successfully in the VM and `podman-zigbee2mqtt` proceeds into real container startup.
- Added a Mosquitto ACME credential shim so the shared Cloudflare secret can satisfy both Caddy (`CLOUDFLARE_API_TOKEN`) and lego (`CLOUDFLARE_DNS_API_TOKEN`).
- Added a Zigbee2MQTT production guardrail so `frame1` evaluation fails if the coordinator path is still the `/dev/serial/by-id/usb-CHANGEME` placeholder; `frame1-vm` explicitly allows the placeholder for local validation.
- Extended the Mosquitto module with ACME passthrough knobs (`dnsResolver`, `dnsPropagationCheck`, and raw `lego` flags) so the remaining Cloudflare/DNS issue can be tuned in production config without another module patch.
- Queried `frame1` over SSH and replaced the Zigbee coordinator placeholder in production config with the stable Sonoff by-id path.
- Fixed the Cloudflare ACME challenge chain for MQTT by creating an explicit `_acme-challenge.mqtt.frame1.hobitin.eu` CNAME to `_acme-challenge-mqtt.hobitin.eu`, which avoids the `*.frame1.hobitin.eu -> frame1.opah-wage.ts.net` wildcard/Tailscale chain.
- Re-ran `acme-order-renew-mqtt.frame1.hobitin.eu.service` on `frame1`; certificate issuance succeeded and the new cert/key were installed under `/var/lib/acme/mqtt.frame1.hobitin.eu/`.
- VM runtime check results:
  - `mosquitto.service` is running
  - `caddy.service` is running with internal TLS
  - `home.frame1.hobitin.eu` and `zigbee.frame1.hobitin.eu` now reach Caddy and return `502` while containers are still pulling/starting
  - MQTT ACME now gets past the missing-env-var failure and fails later on Cloudflare zone lookup (`ts.net.`), indicating a credential or DNS-zone issue outside the module wiring

### 2026-03-27

- Reproduced the homepage navigation bug from `https://frame1.hobitin.eu`: dashboard cards were generating `:8443` URLs such as `https://home.frame1.hobitin.eu:8443`, which refused connections in production.
- Added `homelab.services.homepage.publicHttpsPort` so dashboard cards default to normal HTTPS in production and the VM overlay can still opt into host-mapped port `8443`.
- Updated the Grafana, VictoriaMetrics, Home Assistant, and Zigbee2MQTT homepage registrations to derive their dashboard URLs from that shared setting instead of hardcoding `:8443`.

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
