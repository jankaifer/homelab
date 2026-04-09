# Frigate NVR

Frigate-based camera NVR scaffold for the homelab.

## Status

**Enabled:** Yes in `frame1-vm`, no on `frame1`  
**State:** Mock-camera integration enabled in the VM, production still waiting on real camera definitions

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
  enable = false;
  domain = "frigate.frame1.hobitin.eu";
  recordingsDir = "/nas/nvr/frigate";
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
      enabled = false;
      width = 1280;
      height = 720;
      fps = 5;
    };
  };
  extraSettings.birdseye.enabled = false;
};
```

## Runtime Model

- Uses the upstream NixOS `services.frigate` module
- Keeps Frigate state in `/var/lib/frigate`
- Stores media-oriented data under `/nas/nvr/frigate`
- Symlinks `/var/lib/frigate/clips`, `/var/lib/frigate/exports`, and `/var/lib/frigate/recordings` into the NAS-backed retention path
- Publishes Frigate only through Caddy on `https://frigate.frame1.hobitin.eu`
- In `frame1-vm`, records against the mock RTSP source and stores media in `/var/lib/frigate-test-media`

## Current Blockers

- No real RTSP camera definitions are committed yet
- No Frigate-specific MQTT credential path is defined yet
- Because of that, the service is intentionally left disabled on `frame1` even though the VM path is active

## Access Model

- Primary UI: Frigate web interface
- Access path: private HTTPS via Caddy
- Intended remote path: Tailscale to Caddy, not public internet exposure

## Access

| Environment | URL |
|-------------|-----|
| VM / Local | https://frigate.frame1.hobitin.eu:8443 |
| Production | reserved, not enabled yet |

## Storage Policy

- Recordings, clips, and exports live under `/nas/nvr/frigate`
- These files are retention-only and are not currently in offsite backup scope
- Frigate state remains local under `/var/lib/frigate`

## Dependencies

- Caddy reverse proxy
- NAS layout if using the default `/nas/nvr/frigate` path
- Real camera stream definitions before enablement

## Next Steps

1. Add real camera definitions under `homelab.services.frigate.cameras`
2. Decide whether Frigate should publish events to MQTT on day one
3. Validate the mock-camera path in the VM at runtime
4. Replace the mock stream with real camera inputs for `frame1`
5. Build and boot the VM or deploy to `frame1` once the production camera inputs exist

## Links

- [Frigate](https://frigate.video/)
- [Frigate Configuration Reference](https://docs.frigate.video/configuration/index/)
- [NixOS Frigate Module](https://search.nixos.org/options?show=services.frigate.enable)
