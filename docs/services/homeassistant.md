# Home Assistant Core

Home Assistant Core running in a Podman container with host networking.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/homeassistant.nix`  
**Pattern:** `homelab.services.homeassistant.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.homeassistant.enable` | bool | false | Enable Home Assistant |
| `homelab.services.homeassistant.image` | string | `ghcr.io/home-assistant/home-assistant:2025.2.5` | Container image |
| `homelab.services.homeassistant.port` | int | 8123 | Home Assistant HTTP port |
| `homelab.services.homeassistant.domain` | string | `home.frame1.hobitin.eu` | Caddy-routed domain |
| `homelab.services.homeassistant.dataDir` | path | `/var/lib/homeassistant` | Persistent config/data path |

**Current configuration:**
```nix
homelab.services.homeassistant = {
  enable = true;
  # domain = "home.frame1.hobitin.eu";
  # port = 8123;
  # dataDir = "/var/lib/homeassistant";
};
```

## Runtime Model

- Managed by `virtualisation.oci-containers` (Podman backend)
- Host networking enabled (`--network=host`) for discovery compatibility
- Persistent data in `/var/lib/homeassistant` mounted to `/config`

## Access

| Environment | URL |
|-------------|-----|
| VM / Local | https://home.frame1.hobitin.eu:8443 |
| Production | https://home.frame1.hobitin.eu |

## MQTT Integration (Manual in UI)

Use these values in Home Assistant MQTT integration:
- Broker: `mqtt.frame1.hobitin.eu`
- Port: `8883`
- TLS enabled
- CA certificate: `/var/lib/acme/mqtt.frame1.hobitin.eu/fullchain.pem`
- Username: `homeassistant`
- Password: value from `/run/agenix/mqtt-homeassistant-password`

## Troubleshooting

Check container logs:
```bash
journalctl -u podman-homeassistant -n 200 --no-pager
```

Check local listener:
```bash
ss -ltnp | rg 8123
```

Open UI locally:
```bash
curl -I http://127.0.0.1:8123
```

## Dependencies

- Caddy reverse proxy
- Mosquitto MQTT broker (for smart-home MQTT integration)

## Links

- [Home Assistant](https://www.home-assistant.io/)
- [Container Installation](https://www.home-assistant.io/installation/linux#install-home-assistant-container)
