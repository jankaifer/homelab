# Ticket 015: Add Home Assistant Core Module (Podman, Host Networking)

**Status**: DONE
**Created**: 2026-02-08
**Updated**: 2026-03-27

## Task

Add Home Assistant Core as a Podman-managed OCI container using host networking for maximum discovery compatibility, routed through Caddy.

## Implementation Plan

1. Create `modules/services/homeassistant.nix`
2. Run Home Assistant Core container with:
   - Pinned image
   - Persistent `/config` storage
   - Host networking
3. Add Caddy route for `home.frame1.hobitin.eu`
4. Register service in Homepage dashboard
5. Add service documentation

## Work Log

### 2026-02-08

- Created `modules/services/homeassistant.nix` with `homelab.services.homeassistant.*` options
- Added containerized Home Assistant Core with `--network=host`
- Added persistent data dir setup via tmpfiles
- Added Caddy reverse proxy integration and Homepage registration

### 2026-03-27

- Added `homeassistant-config.service` so the baseline Home Assistant config is generated declaratively and trusted proxy handling stays in sync with the reverse proxy setup
- Completed first-run onboarding on `frame1`
- Created a production admin account for Home Assistant and stored the generated password in `secrets/homeassistant-admin-password.age`
- Verified the UI is reachable at `https://home.frame1.hobitin.eu`

## Validation Notes

- Passed on 2026-03-27:
  - Home Assistant reachable via `https://home.frame1.hobitin.eu`
  - Baseline config passes `python -m homeassistant --script check_config --config /config`
  - Instance has a completed onboarding state and a working admin login
