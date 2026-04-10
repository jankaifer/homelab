# Frigate NVR

Frigate-based camera NVR scaffold for the homelab.

## Status

**Enabled:** Yes in `frame1-vm` and on `frame1`  
**State:** Enabled against a synthetic RTSP source pending real camera definitions

## Configuration

**Module:** `modules/services/frigate.nix`  
**Pattern:** `homelab.services.frigate.enable`

**Options:**


| Option                                   | Type         | Default                     | Description                                      |
| ---------------------------------------- | ------------ | --------------------------- | ------------------------------------------------ |
| `homelab.services.frigate.enable`               | bool         | false                       | Enable Frigate                                   |
| `homelab.services.frigate.domain`               | string       | `frigate.frame1.hobitin.eu` | Private Caddy-routed hostname                    |
| `homelab.services.frigate.recordingsDir`        | string       | `/nas/nvr/frigate`          | Retention-oriented media storage                 |
| `homelab.services.frigate.retainDays`           | unsigned int | `7`                         | Motion recording retention window for newer Frigate versions |
| `homelab.services.frigate.continuousRetainDays`| unsigned int | `3`                         | Continuous recording retention window            |
| `homelab.services.frigate.retainMode`          | enum         | `"all"`                     | Base retention mode used by the deployed Frigate version |
| `homelab.services.frigate.reviewRetainDays`     | unsigned int | `365`                       | Retention for alert/detection review segments    |
| `homelab.services.frigate.reviewRetainMode`     | enum         | `"motion"`                  | How much video around review events to keep      |
| `homelab.services.frigate.cameras`              | attrset      | `{}`                        | Camera definitions passed to Frigate             |
| `homelab.services.frigate.extraSettings`        | attrset      | `{}`                        | Additional Frigate settings merged over defaults |
| `homelab.services.frigate.snapshots.*`          | attrs        | see module                  | Snapshot enablement plus retention controls      |
| `homelab.services.frigate.mqtt.*`               | attrs        | see module                  | Optional secret-backed MQTT publishing for Frigate events and stats |


**Current machine configuration:**

```nix
homelab.services.frigate = {
  enable = true;
  domain = "frigate.frame1.hobitin.eu";
  recordingsDir = "/nas/nvr/frigate";
  continuousRetainDays = 3;
  retainMode = "all";
  reviewRetainDays = 365;
  cameras.mock_driveway = {
    ffmpeg.inputs = [{
      path = "rtsp://127.0.0.1:8554/mock-driveway";
      input_args = "preset-rtsp-restream";
      roles = [ "detect" "record" ];
    }];
    detect = {
      enabled = true;
      width = 1280;
      height = 720;
      fps = 5;
    };
  };
  extraSettings = {
    birdseye.enabled = false;
    ffmpeg.hwaccel_args = "preset-vaapi";
    objects.track = [ "person" "car" "bicycle" ];
  };
  snapshots = {
    retainDays = 7;
    cleanCopy = false;
  };
  mqtt = {
    enable = true;
    host = "127.0.0.1";
    port = 1883;
    passwordFile = config.age.secrets.mqtt-frigate-password.path;
  };
};
```

**Current VM testing configuration:**

```nix
homelab.services.frigate = {
  enable = true;
  recordingsDir = "/var/lib/frigate-test-media";
  continuousRetainDays = 3;
  retainMode = "all";
  reviewRetainDays = 365;
  cameras.mock_driveway = {
    ffmpeg.inputs = [{
      path = "rtsp://127.0.0.1:8554/mock-driveway";
      input_args = "preset-rtsp-restream";
      roles = [ "detect" "record" ];
    }];
    detect = {
      enabled = true;
      width = 1280;
      height = 720;
      fps = 5;
    };
  };
  extraSettings = {
    birdseye.enabled = false;
    objects.track = [ "person" "car" "bicycle" ];
  };
  snapshots = {
    retainDays = 7;
    cleanCopy = false;
  };
};
```

## Runtime Model

- Uses the upstream NixOS `services.frigate` module
- Keeps Frigate state in `/var/lib/frigate`
- Stores media-oriented data under `/nas/nvr/frigate`
- Defaults to `3` days of base continuous retention and one-year review retention
- Caps snapshot retention to one week and disables clean-copy duplicates
- Symlinks `/var/lib/frigate/clips`, `/var/lib/frigate/exports`, and `/var/lib/frigate/recordings` into the NAS-backed retention path
- Extends the internal nginx unit with the NAS shared group when recordings live under `/nas` so review/history media remains readable through the UI
- On `frame1`, enables Intel VA-API decode with `intel-media-driver`, `services.frigate.vaapiDriver = "iHD"`, and `ffmpeg.hwaccel_args = "preset-vaapi"`
- Publishes Frigate only through Caddy on `https://frigate.frame1.hobitin.eu`
- Renders the final Frigate runtime config in `/run/frigate/frigate.yml` so the MQTT password can come from agenix instead of the Nix store
- In `frame1-vm`, records against the mock RTSP source and stores media in `/var/lib/frigate-test-media`
- On `frame1`, records against the same mock RTSP source while real camera URLs are still pending

## Current Blockers

- No real RTSP camera definitions are committed yet
- Production currently uses a synthetic RTSP stream instead of a real camera feed

## Access Model

- Primary UI: Frigate web interface
- Access path: private HTTPS via Caddy
- Intended remote path: Tailscale to Caddy, not public internet exposure

## Access


| Environment | URL                                                                              |
| ----------- | -------------------------------------------------------------------------------- |
| VM / Local  | [https://frigate.frame1.hobitin.eu:8443](https://frigate.frame1.hobitin.eu:8443) |
| Production  | [https://frigate.frame1.hobitin.eu](https://frigate.frame1.hobitin.eu)           |


## Storage Policy

- Recordings, clips, and exports live under `/nas/nvr/frigate`
- These files are retention-only and are not currently in offsite backup scope
- Frigate state remains local under `/var/lib/frigate`
- Default retention profile:
  - Continuous recordings: `3` days
  - Alert/detection review segments: `365` days
  - Snapshots: `7` days
- Current limitation: the packaged Frigate `0.16.3` config schema does not support separate base `continuous` and `motion` retention windows, so the generic `7`-day motion target cannot be expressed until Frigate is upgraded.

## Disk Reduction Levers

- Keep `continuousRetainDays = 0` unless you explicitly need a full rolling archive
- Lower `retainDays` further if generic motion footage still dominates the NAS
- Lower `reviewRetainDays` if review/history clips remain the main consumer
- Set `snapshots.enable = false` if Frigate snapshots are not needed by Home Assistant or notifications
- Keep `snapshots.cleanCopy = false` to avoid duplicate stored images
- When real cameras are added, use a low-bitrate substream for `detect` and keep the main stream for `record`
- The current synthetic `mock_driveway` stream is noisier than a tuned real camera and can overstate expected disk growth during testing

## Dependencies

- Caddy reverse proxy
- NAS layout if using the default `/nas/nvr/frigate` path
- Real camera stream definitions before replacing the synthetic source

## Next Steps

1. Replace the synthetic RTSP source with real camera definitions under `homelab.services.frigate.cameras`
2. Validate the lower-retention profile at runtime and tune per camera once real streams are available
3. Confirm Home Assistant sees Frigate MQTT entities/events through the existing broker integration
4. Keep only the cameras and review windows that are operationally useful once the synthetic source is removed

## Links

- [Frigate](https://frigate.video/)
- [Frigate Configuration Reference](https://docs.frigate.video/configuration/index/)
- [NixOS Frigate Module](https://search.nixos.org/options?show=services.frigate.enable)
