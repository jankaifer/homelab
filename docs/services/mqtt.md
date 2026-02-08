# MQTT (Mosquitto)

TLS-enabled MQTT broker for Home Assistant and Zigbee2MQTT.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/mosquitto.nix`  
**Pattern:** `homelab.services.mosquitto.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.mosquitto.enable` | bool | false | Enable Mosquitto |
| `homelab.services.mosquitto.tlsPort` | int | 8883 | TLS MQTT listener port |
| `homelab.services.mosquitto.domain` | string | `mqtt.frame1.hobitin.eu` | Domain used for ACME certificate |
| `homelab.services.mosquitto.acmeEmail` | string or null | null | ACME registration email |
| `homelab.services.mosquitto.cloudflareDnsTokenFile` | path or null | null | Cloudflare DNS challenge env file |
| `homelab.services.mosquitto.homeAssistantPasswordFile` | path or null | null | Password file for `homeassistant` user |
| `homelab.services.mosquitto.zigbee2mqttPasswordFile` | path or null | null | Password file for `zigbee2mqtt` user |
| `homelab.services.mosquitto.allowLAN` | bool | true | Open listener for LAN clients |
| `homelab.services.mosquitto.allowTailscale` | bool | true | Allow listener via tailscale interface |

**Current configuration:**
```nix
homelab.services.mosquitto = {
  enable = true;
  domain = "mqtt.frame1.hobitin.eu";
  tlsPort = 8883;
  acmeEmail = "jan@kaifer.cz";
  cloudflareDnsTokenFile = config.age.secrets.cloudflare-api-token.path;
  homeAssistantPasswordFile = config.age.secrets.mqtt-homeassistant-password.path;
  zigbee2mqttPasswordFile = config.age.secrets.mqtt-zigbee2mqtt-password.path;
};
```

## TLS Certificates

Certificates are issued and renewed by NixOS `security.acme` using Cloudflare DNS challenge.

Certificate paths used by Mosquitto:
- `/var/lib/acme/mqtt.frame1.hobitin.eu/fullchain.pem`
- `/var/lib/acme/mqtt.frame1.hobitin.eu/key.pem`

On renewal, Mosquitto is reloaded automatically.

## Users and ACL

Configured users:
- `homeassistant`
- `zigbee2mqtt`

ACL scope:
- `homeassistant/#`
- `zigbee2mqtt/#`

## Access

MQTT over TLS:
- `mqtt.frame1.hobitin.eu:8883`

## Troubleshooting

Check broker status:
```bash
systemctl status mosquitto
journalctl -u mosquitto -n 200 --no-pager
```

Verify certificate files:
```bash
ls -l /var/lib/acme/mqtt.frame1.hobitin.eu/
```

Test TLS subscription:
```bash
mosquitto_sub \
  -h mqtt.frame1.hobitin.eu \
  -p 8883 \
  --cafile /var/lib/acme/mqtt.frame1.hobitin.eu/fullchain.pem \
  -u zigbee2mqtt \
  -P "$(cat /run/agenix/mqtt-zigbee2mqtt-password)" \
  -t 'zigbee2mqtt/#' -v
```

## Dependencies

- Cloudflare API token secret for ACME DNS challenge
- NixOS ACME (`security.acme`)

## Links

- [Mosquitto](https://mosquitto.org/)
- [Mosquitto Configuration](https://mosquitto.org/man/mosquitto-conf-5.html)
- [NixOS ACME](https://nixos.org/manual/nixos/stable/#module-security-acme)
