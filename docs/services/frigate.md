# Frigate NVR

Frigate-based camera NVR scaffold for the homelab.

## Status

**Enabled:** Yes in `frame1-vm` and on `frame1`  
**State:** Enabled against a synthetic RTSP source pending real camera definitions

## Configuration

**Module:** `modules/services/frigate.nix`  
**Pattern:** `homelab.services.frigate.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.frigate.enable` | bool | false | Enable Frigate |
| `homelab.services.frigate.domain` | string | `frigate.frame1.hobitin.eu` | Private Caddy-routed hostname |
| `homelab.services.frigate.recordingsDir` | string | `/nas/nvr/frigate` | Retention-oriented media storage |
| `homelab.services.frigate.retainDays` | unsigned int | `14` | Default recording retention window |
| `homelab.services.frigate.cameras` | attrset | `{}` | Camera definitions passed to Frigate |
| `homelab.services.frigate.extraSettings` | attrset | `{}` | Additional Frigate settings merged over defaults |

**Current machine configuration:**
```nix
homelab.services.frigate = {
  enable = true;
  domain = "frigate.frame1.hobitin.eu";
  recordingsDir = "/nas/nvr/frigate";
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
};
```

**Current VM testing configuration:**
```nix
homelab.services.frigate = {
  enable = true;
  recordingsDir = "/var/lib/frigate-test-media";
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
};
```

## Runtime Model

- Uses the upstream NixOS `services.frigate` module
- Keeps Frigate state in `/var/lib/frigate`
- Stores media-oriented data under `/nas/nvr/frigate`
- Symlinks `/var/lib/frigate/clips`, `/var/lib/frigate/exports`, and `/var/lib/frigate/recordings` into the NAS-backed retention path
- Publishes Frigate only through Caddy on `https://frigate.frame1.hobitin.eu`
- In `frame1-vm`, records against the mock RTSP source and stores media in `/var/lib/frigate-test-media`
- On `frame1`, records against the same mock RTSP source while real camera URLs are still pending

## Current Blockers

- No real RTSP camera definitions are committed yet
- No Frigate-specific MQTT credential path is defined yet
- Production currently uses a synthetic RTSP stream instead of a real camera feed

## Access Model

- Primary UI: Frigate web interface
- Access path: private HTTPS via Caddy
- Intended remote path: Tailscale to Caddy, not public internet exposure

## Access

| Environment | URL |
|-------------|-----|
| VM / Local | https://frigate.frame1.hobitin.eu:8443 |
| Production | https://frigate.frame1.hobitin.eu |

## Storage Policy

- Recordings, clips, and exports live under `/nas/nvr/frigate`
- These files are retention-only and are not currently in offsite backup scope
- Frigate state remains local under `/var/lib/frigate`

## Dependencies

- Caddy reverse proxy
- NAS layout if using the default `/nas/nvr/frigate` path
- Real camera stream definitions before replacing the synthetic source

## Next Steps

1. Replace the synthetic RTSP source with real camera definitions under `homelab.services.frigate.cameras`
2. Decide whether Frigate should publish events to MQTT on day one
3. Validate the mock-camera path at runtime in both VM and production
4. Wire Frigate into MQTT if Home Assistant entities/events are needed

## Links

- [Frigate](https://frigate.video/)
- [Frigate Configuration Reference](https://docs.frigate.video/configuration/index/)
- [NixOS Frigate Module](https://search.nixos.org/options?show=services.frigate.enable)
