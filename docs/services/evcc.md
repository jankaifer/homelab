# evcc

EV charging and loadpoint service for the homelab energy stack.

## Status

**Enabled:** Yes, in first-rollout commissioning mode

## Configuration

**Module:** `modules/services/evcc.nix`  
**Pattern:** `homelab.services.evcc.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.evcc.enable` | bool | false | Enable evcc |
| `homelab.services.evcc.port` | int | 7070 | Internal UI/API port |
| `homelab.services.evcc.listenAddress` | string | `127.0.0.1` | Host value advertised by evcc |
| `homelab.services.evcc.domain` | string | `evcc.frame1.hobitin.eu` | Caddy-routed domain |
| `homelab.services.evcc.siteTitle` | string | `Frame1` | UI site title |
| `homelab.services.evcc.demoMode` | bool | true | Run with simulated demo devices |
| `homelab.services.evcc.restrictNetworkToLoopback` | bool | true | Restrict evcc networking to loopback with systemd filtering |
| `homelab.services.evcc.settings` | attrs | `{}` | Extra evcc YAML settings merged over defaults |
| `homelab.services.evcc.mqtt.enable` | bool | true | Publish evcc state to MQTT |
| `homelab.services.evcc.mqtt.host` | string | `127.0.0.1` | MQTT broker host |
| `homelab.services.evcc.mqtt.port` | int | 1883 | MQTT broker port |
| `homelab.services.evcc.mqtt.topic` | string | `evcc` | MQTT topic prefix |
| `homelab.services.evcc.mqtt.username` | string | `evcc` | MQTT username |
| `homelab.services.evcc.mqtt.passwordFile` | path or null | null | Raw agenix password file for MQTT |

Current production wiring:

```nix
homelab.services.evcc = {
  enable = true;
  domain = "evcc.frame1.hobitin.eu";
  mqtt.passwordFile = config.age.secrets.mqtt-evcc-password.path;
};
```

## Access

- URL: `https://evcc.frame1.hobitin.eu`
- Internal UI/API: `127.0.0.1:7070`
- Systemd service: `evcc.service`
- State directory: `/var/lib/evcc`

The service is exposed through Caddy and is not opened directly in the firewall.
evcc itself listens on all interfaces for its configured port, so the homelab
wrapper also applies systemd `IPAddressDeny=any` with `IPAddressAllow=localhost`
by default during commissioning.

## First-Rollout Boundary

The first rollout is intentionally non-actuating:

- `demoMode = true` starts evcc with simulated devices.
- No real charger is configured.
- No real loadpoint is configured with a write-capable charger.
- No wallbox API credentials are present.
- No OCPP endpoint is configured for a real charger.
- No vehicle API credentials are present.
- MQTT is used for EVCC state under `evcc/#`; no MQTT command topics are wired to automations.

Future active-control work must be tracked in a separate ticket before adding charger, vehicle, wallbox, OCPP, or write-capable API credentials.

## MQTT

evcc uses the dedicated `evcc` MQTT user against the loopback Mosquitto listener:

- Broker: `127.0.0.1:1883`
- Topic prefix: `evcc`
- Password secret: `secrets/mqtt-evcc-password.age`

The homelab wrapper generates a runtime-only environment file at `/run/evcc-secrets/mqtt.env` from the raw agenix password so the MQTT password is substituted into the generated evcc config without entering the Nix store.

## Troubleshooting

Check service status:

```bash
systemctl status evcc
journalctl -u evcc -n 200 --no-pager
```

Check the MQTT env preparation service:

```bash
systemctl status evcc-mqtt-env
journalctl -u evcc-mqtt-env -n 50 --no-pager
```

Verify the UI listener:

```bash
ss -ltnp | grep ':7070'
```

## Dependencies

- NixOS upstream `services.evcc`
- Mosquitto loopback listener on `127.0.0.1:1883`
- `secrets/mqtt-evcc-password.age`
- Caddy for external HTTPS routing

## Links

- [evcc documentation](https://docs.evcc.io/)
- [evcc configuration reference](https://docs.evcc.io/en/docs/reference/configuration)
- [NixOS evcc module](https://search.nixos.org/options?query=services.evcc)
