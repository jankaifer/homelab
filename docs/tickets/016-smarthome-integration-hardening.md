# Ticket 016: Smart-Home Integration, Hardening, and Validation

**Status**: DONE
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
- Verified on `frame1` that `/etc/homepage-dashboard/services.yaml` updated during deploy but `homepage-dashboard.service` did not restart, so the app kept serving stale links from its old process state.
- Added `systemd.services.homepage-dashboard.restartTriggers` for the generated Homepage YAML/assets so future deploys restart the dashboard when its config changes.
- Confirmed `grafana.local.hobitin.eu` does not resolve from the public/Tailscale browser path used for `frame1.hobitin.eu`, so production overrides now use `grafana.frame1.hobitin.eu` and `metrics.frame1.hobitin.eu` on `frame1`.
- Upgraded the Sonoff ZBDongle-E coordinator on `frame1` from EmberZNet `6.10.3.0 build 297` to `7.4.4 [GA]`, which resolves the `EZSP protocol version (8) is not supported by Host [13-14]` startup failure in Zigbee2MQTT.
- After the firmware fix, identified a second runtime issue: the bridged Zigbee2MQTT container resolved `mqtt.frame1.hobitin.eu` to its own loopback (`127.0.0.1`) and could not reach Mosquitto. Switched the container to host networking so the broker TLS hostname pinned on `frame1` works from inside Zigbee2MQTT too.
- Identified a third runtime issue after host networking: Zigbee2MQTT was treating the broker leaf/full-chain cert as a CA bundle and failed TLS verification with `unable to get issuer certificate`. Made `mqtt.caFile` optional so production can use the container's built-in public trust store for the Let's Encrypt broker cert.
- Added a declarative Home Assistant baseline config generator instead of relying on the container's first-run defaults.
- Rotated both MQTT client passwords away from placeholder values and re-encrypted them into agenix secrets.
- Added a loopback-only Mosquitto listener on `127.0.0.1:1883` so Home Assistant can use the supported UI config flow locally while Zigbee2MQTT and remote clients stay on the TLS listener.
- Completed Home Assistant onboarding on `frame1`, stored the generated admin password in `secrets/homeassistant-admin-password.age`, and added the MQTT integration through the UI.
- Verified Home Assistant now has an `mqtt` config entry and Zigbee2MQTT bridge entities in the entity registry.
- Added restart triggers for both `podman-homeassistant` and `podman-zigbee2mqtt` so generated config and MQTT secret rotations actually restart the dependent services on deploy.

## Smoke-Check Runbook

1. Validate and build:
   - `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
   - `./scripts/run-vm-docker.sh --build`
2. Deploy:
   - `nix run .#deploy -- .#frame1 --skip-checks`
3. MQTT checks on frame1:
   - `nix shell nixpkgs#mosquitto -c mosquitto_sub -h mqtt.frame1.hobitin.eu -p 8883 -u zigbee2mqtt -P "$(cat /run/agenix/mqtt-zigbee2mqtt-password)" -t 'zigbee2mqtt/bridge/state' -C 1 -W 5`
   - Verify invalid password is rejected with `Connection Refused: not authorised`
4. Zigbee adapter check:
   - `ls -l /dev/serial/by-id/`
   - `journalctl -u podman-zigbee2mqtt -n 200 --no-pager`
5. HA flow:
   - Open `https://home.frame1.hobitin.eu`
   - Log in with the admin credential stored in `secrets/homeassistant-admin-password.age`
   - Verify the MQTT integration exists and Zigbee2MQTT bridge entities appear
