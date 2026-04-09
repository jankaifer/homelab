# Ticket 022: First Frigate Deployment

**Status**: IN_PROGRESS
**Created**: 2026-03-31
**Updated**: 2026-04-09

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
- Added a VM-only mock RTSP camera source at `rtsp://127.0.0.1:8554/mock-driveway` for Frigate integration testing without hardware.
- Verified the `frame1-vm` Docker build still completes successfully with the mock RTSP camera services included.
- Enabled a VM-only Frigate test camera that consumes the mock RTSP stream so the camera integration path is now exercised end to end in `frame1-vm`.
- Enabled the same synthetic RTSP source and Frigate test camera on `frame1` so the private production UI and NAS-backed recordings path can be verified before real cameras are added.

### 2026-04-09

- Investigated Frigate review/history loading failures on `frame1`.
- Confirmed the API itself was reachable through Caddy, while nginx logged `Permission denied` when serving review/history media from `/var/lib/frigate/...`.
- Fixed the NAS-backed storage path by adding the NAS shared group to the nginx systemd unit when Frigate recordings are stored under `/nas`.
- Enabled Intel iGPU video decode on `frame1` by turning on `hardware.graphics`, adding `intel-media-driver`, setting `services.frigate.vaapiDriver = "iHD"`, and applying Frigate `ffmpeg.hwaccel_args = "preset-vaapi"`.
