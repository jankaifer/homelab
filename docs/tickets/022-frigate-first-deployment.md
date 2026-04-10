# Ticket 022: First Frigate Deployment

**Status**: DONE
**Created**: 2026-03-31
**Updated**: 2026-04-10

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
- Ticket completion means the first private Frigate deployment is live, reproducible from NixOS configuration, and verified on `frame1` with the synthetic camera path.
- A future follow-on can still add real camera definitions and a first-class Home Assistant Frigate integration, but those are no longer blockers for closing this rollout ticket.

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
- Reduced mock-camera Frigate detection from `5` FPS to `1` FPS in both production and VM configs to cut CPU load while keeping the integration path active.
- Changed the mock RTSP `detection-demo` publisher to pre-transcode the sample clip once during the Nix build and then stream the cached file with `-c:v copy`, avoiding continuous `libx264` re-encoding on `frame1`.
- Added a Frigate-specific MQTT credential path in the homelab modules and Mosquitto ACLs so Frigate can publish under `frigate/#` without sharing another client's broker credentials.
- Switched the Frigate wrapper to render its final runtime config under `/run/frigate/frigate.yml`, which keeps the MQTT password out of the Nix store while preserving declarative Frigate settings.
- Enabled Frigate MQTT publishing on `frame1` against the host-local Mosquitto loopback listener so Home Assistant can consume Frigate events through the existing broker integration.
- After the first deploy, verified on `frame1` that Frigate was still crash-looping because the upstream `frigate-create-writable-config` `ExecStartPre` step overwrote the secret-injected runtime config and dropped the MQTT password.
- Replaced the upstream Frigate `ExecStartPre` list in the homelab wrapper so the final `/run/frigate/frigate.yml` is rendered from the runtime template after cache cleanup, preserving the MQTT password from agenix on every start.
- Verified a second runtime regression after the secret-rendering change: the homelab wrapper had stopped carrying forward Frigate's `ffmpeg.path`, so Frigate fell back to its internal `default/bin/ffmpeg` lookup and the mock camera ingest path failed.
- Restored an explicit Nix-managed `ffmpeg.path` in the Frigate wrapper defaults so the generated runtime config still points at the store-provided ffmpeg package when rendered outside the upstream module's built-in config generator.
- Increased the mock RTSP publisher from `10` FPS to `30` FPS in both production and VM configs so the live stream remains close to real-time for UI viewing, while Frigate detection stays capped at `1` FPS.
- Raised the Frigate mock-camera detection rate from `1` FPS to `5` FPS after verifying the host can afford the extra inference load, which should improve live-view responsiveness without changing the full-rate recording stream.
- Investigated Frigate disk-growth controls from the repo side after a direct SSH probe to `192.168.2.241` timed out, so live on-host `du` numbers could not be collected from this workspace.
- Reworked the homelab Frigate defaults to match Frigate's newer storage controls: no continuous retention, `3` days of motion retention, `14` days for alert/detection review segments, and `7` days for snapshots.
- Added explicit snapshot retention controls to the Frigate module and kept `snapshots.cleanCopy = false` so Frigate does not store duplicate clean-copy images by default.
- Applied the tighter retention profile to both `frame1` and `frame1-vm` so the same lower-disk behavior is exercised in the test environment.
- Updated the retention profile again after sizing review: `3` days of continuous retention, `7` days of motion retention, and `365` days for alert/detection review segments.
- The subsequent deploy exposed a Frigate `0.16.3` schema limitation: the packaged version does not accept separate base `continuous` and `motion` retention windows yet, so the deployed compromise keeps `3` days of base retention plus `365` days for alert/detection review segments.
- Disabled Frigate's build-time config validation in the homelab wrapper because the checker cannot see the MQTT password that is injected later at runtime from agenix.

### 2026-04-10

- Verified on `frame1` that the deployed Frigate UI is reachable through Caddy at `https://frigate.frame1.hobitin.eu` and the local API responds as expected.
- Verified the runtime-generated Frigate config now includes both the agenix-backed MQTT password and the Nix-store ffmpeg path, keeping the deployment reproducible without host-local manual fixes.
- Verified Frigate publishes MQTT topics under `frigate/#`, and confirmed the Home Assistant MQTT credentials can subscribe to those topics through the existing broker ACLs.
- Increased the mock RTSP publisher to `30` FPS while keeping Frigate detection at `5` FPS, improving live-view responsiveness without changing the overall declarative camera setup.
- Re-deployed and verified the final `frame1` generation with Frigate, Mosquitto, Caddy, MediaMTX, and the mock RTSP publisher all active.
