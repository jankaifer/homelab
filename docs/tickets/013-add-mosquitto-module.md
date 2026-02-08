# Ticket 013: Add Mosquitto Module with ACME TLS + ACL Auth

**Status**: IN_PROGRESS
**Created**: 2026-02-08
**Updated**: 2026-02-08

## Task

Add a reusable Mosquitto service module with TLS, username/password auth, ACL policy, and automatic certificate issuance via NixOS ACME using Cloudflare DNS challenge.

## Implementation Plan

1. Create `modules/services/mosquitto.nix`
2. Configure `security.acme.certs."mqtt.frame1.hobitin.eu"`:
   - `dnsProvider = "cloudflare"`
   - `environmentFile = <cloudflare token secret path>`
   - `reloadServices = [ "mosquitto" ]`
3. Add TLS listener on port `8883`
4. Configure users/password files for Home Assistant and Zigbee2MQTT
5. Configure ACL scope and firewall exposure policy (LAN + Tailscale)
6. Add service documentation

## Work Log

### 2026-02-08

- Created `modules/services/mosquitto.nix` with `homelab.services.mosquitto.*` options
- Added ACME certificate management for `mqtt.frame1.hobitin.eu` via Cloudflare DNS challenge
- Added TLS listener with cert/key from `/var/lib/acme/<domain>/`
- Added password-file auth for users:
  - `homeassistant`
  - `zigbee2mqtt`
- Added ACL rules for smart-home topic namespaces
- Added firewall policy options for LAN and Tailscale exposure

## Validation Notes

- Pending runtime checks:
  - TLS handshake success with valid credentials
  - Rejection with invalid credentials
  - ACL negative tests
