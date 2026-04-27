# EOS Connect

EOS Connect advisory orchestration dashboard between Akkudoktor EOS, evcc, Home Assistant, and MQTT.

## Status

**Enabled:** Yes, advisory/read-only first rollout

## Configuration

**Module:** `modules/services/eos-connect.nix`  
**Pattern:** `homelab.services.eosConnect.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.eosConnect.enable` | bool | false | Enable EOS Connect |
| `homelab.services.eosConnect.image` | string | `ghcr.io/ohand/eos_connect:latest` | Container image |
| `homelab.services.eosConnect.port` | int | 8081 | EOS Connect web UI port |
| `homelab.services.eosConnect.domain` | string | `eos-connect.frame1.hobitin.eu` | Caddy-routed domain |
| `homelab.services.eosConnect.dataDir` | string | `/var/lib/eos-connect` | Persistent data directory |
| `homelab.services.eosConnect.timeZone` | string | `config.time.timeZone` | Runtime timezone |
| `homelab.services.eosConnect.logLevel` | enum | `INFO` | Log level |
| `homelab.services.eosConnect.mqtt.enable` | bool | true | Reserve EOS Connect MQTT identity |
| `homelab.services.eosConnect.mqtt.passwordFile` | path or null | null | Raw agenix password file for MQTT |

Production wiring:

```nix
homelab.services.eosConnect = {
  enable = true;
  domain = "eos-connect.frame1.hobitin.eu";
  mqtt.passwordFile = config.age.secrets.mqtt-eos-connect-password.path;
};
```

## Access

- URL: `https://eos-connect.frame1.hobitin.eu`
- Internal UI/API: `127.0.0.1:8081`
- Systemd service: `podman-eos-connect.service`
- Declarative config seed: `eos-connect-bootstrap-config.service`
- State directory: `/var/lib/eos-connect`
- Config file: `/etc/eos-connect/config.yaml`

The container uses host networking so it can reach host-local services such as Akkudoktor EOS, evcc, Home Assistant, and the Mosquitto loopback listener.

EOS Connect persists most settings in `/var/lib/eos-connect/eos_connect.db`.
The homelab module applies the local EOS, evcc, and MQTT settings to that
database before the container starts. The MQTT password is read from agenix at
runtime and is not written into the Nix store.

## MQTT

EOS Connect has a dedicated MQTT identity:

- Username: `eos-connect`
- Password secret: `secrets/mqtt-eos-connect-password.age`
- Read access: `evcc/#`, `homeassistant/#`, `frigate/#`
- Write access: `eos_connect/#` and Home Assistant MQTT discovery/state under `homeassistant/#`

No broad command-topic access is granted in the first rollout.

## Control Boundary

EOS Connect is deployed for observation and advisory planning only:

- no evcc commands
- no Home Assistant service calls
- no MQTT command topics consumed by active automations
- no charger or battery actuation

If active control is added later, it must be handled in a separate ticket with explicit ownership of evcc, Home Assistant, and MQTT command paths.

## Troubleshooting

```bash
systemctl status eos-connect-bootstrap-config
systemctl status podman-eos-connect
journalctl -u podman-eos-connect -n 200 --no-pager
ss -ltnp | grep ':8081'
```

## Dependencies

- Akkudoktor EOS
- evcc
- Home Assistant
- Mosquitto
- Caddy for HTTPS routing

## Links

- [EOS Connect](https://github.com/ohAnd/EOS_connect)
