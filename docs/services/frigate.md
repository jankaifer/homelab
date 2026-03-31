# Frigate NVR

Frigate-based camera NVR scaffold for the homelab.

## Status

**Enabled:** No  
**State:** Module implemented, waiting on real camera definitions

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

## Runtime Model

- Uses the upstream NixOS `services.frigate` module
- Keeps Frigate state in `/var/lib/frigate`
- Stores media-oriented data under `/nas/nvr/frigate`
- Symlinks `/var/lib/frigate/clips`, `/var/lib/frigate/exports`, and `/var/lib/frigate/recordings` into the NAS-backed retention path
- Publishes Frigate only through Caddy on `https://frigate.frame1.hobitin.eu`

## Current Blockers

- No real RTSP camera definitions are committed yet
- No Frigate-specific MQTT credential path is defined yet
- Because of that, the service is intentionally left disabled on `frame1`

## Access Model

- Primary UI: Frigate web interface
- Access path: private HTTPS via Caddy
- Intended remote path: Tailscale to Caddy, not public internet exposure

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
3. Validate the config with `nix eval`
4. Build and boot the VM or deploy to `frame1` once the camera inputs exist

## Links

- [Frigate](https://frigate.video/)
- [Frigate Configuration Reference](https://docs.frigate.video/configuration/index/)
- [NixOS Frigate Module](https://search.nixos.org/options?show=services.frigate.enable)
