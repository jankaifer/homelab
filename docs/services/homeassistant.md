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
| `homelab.services.homeassistant.trustedProxies` | list of string | `[ "127.0.0.1" "::1" ]` | Trusted reverse proxies for Caddy |

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
- Baseline `configuration.yaml` is generated declaratively by `homeassistant-config.service`
- Home Assistant was onboarded on production and now has an initialized admin account

## Access

| Environment | URL |
|-------------|-----|
| VM / Local | https://home.frame1.hobitin.eu:8443 |
| Production | https://home.frame1.hobitin.eu |

## MQTT Integration

Home Assistant 2025 no longer accepts broker connection details in `configuration.yaml`, so the MQTT broker is configured through the UI config flow.

Current production setup:
- Broker: `127.0.0.1`
- Port: `1883`
- Username: `homeassistant`
- Password: value from `/run/agenix/mqtt-homeassistant-password`
- Listener scope: loopback only on `frame1`

Zigbee2MQTT still uses the TLS listener on `mqtt.frame1.hobitin.eu:8883`. Home Assistant uses the local loopback listener because it runs on the same host and the built-in UI flow does not expose the TLS path cleanly enough for unattended setup.

The Home Assistant admin password created during onboarding is stored in [homeassistant-admin-password.age](/Users/jankaifer/dev/jankaifer/homelab/secrets/homeassistant-admin-password.age).

## Troubleshooting

Check container logs:
```bash
journalctl -u podman-homeassistant -n 200 --no-pager
```

Check generated config:
```bash
sed -n '1,200p' /var/lib/homeassistant/configuration.yaml
```

Validate config inside the running container:
```bash
podman exec homeassistant python -m homeassistant --script check_config --config /config
```

Check MQTT config entry:
```bash
grep -n '"domain":"mqtt"' /var/lib/homeassistant/.storage/core.config_entries
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
