# Ticket 022: First Frigate Deployment

**Status**: IN_PROGRESS
**Created**: 2026-03-31
**Updated**: 2026-03-31

## Task

Implement the first camera/NVR deployment based on the architecture decision from Ticket 021. The initial rollout should run Frigate on `frame1`, keep access private behind Tailscale, route the UI through Caddy, and store recordings as local retention-only data.

## Implementation Plan

1. Add a reusable Frigate service module with machine-level enablement on `frame1`
2. Define configuration, secrets, and storage paths for Frigate state and recordings
3. Route the Frigate UI privately through Caddy without public exposure
4. Add basic Home Assistant stream and entity integration
5. Document the deployment, operating model, and storage policy

## Notes

- This is the direct implementation follow-up to Ticket 021.
- Day-one scope excludes accelerator-dependent detection work and public internet exposure.
- Raw recordings remain retention-only data and should not be added to offsite backup.

## Work Log

### 2026-03-31

- Ticket created from the approved camera/NVR architecture decision.
- Scoped specifically to the first private Frigate deployment on `frame1`.
- Added `modules/services/frigate.nix` as a homelab wrapper around the upstream NixOS Frigate service.
- Wired the module into `frame1` with the intended private hostname and NAS-backed recordings path.
- Added service documentation in `docs/services/frigate.md`.
- Kept the service disabled because the repo still lacks real RTSP camera definitions and a Frigate-specific MQTT credential path.
