# Akkudoktor EOS

Akkudoktor EOS optimizer API and dashboard for advisory energy planning.

## Status

**Enabled:** Yes, advisory/read-only first rollout

## Configuration

**Module:** `modules/services/akkudoktor-eos.nix`  
**Pattern:** `homelab.services.akkudoktorEos.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.akkudoktorEos.enable` | bool | false | Enable Akkudoktor EOS |
| `homelab.services.akkudoktorEos.image` | string | `akkudoktor/eos:latest` | Container image |
| `homelab.services.akkudoktorEos.apiPort` | int | 8503 | Host-local EOS API port |
| `homelab.services.akkudoktorEos.dashboardPort` | int | 8504 | Host-local EOS dashboard port |
| `homelab.services.akkudoktorEos.domain` | string | `eos.frame1.hobitin.eu` | Caddy-routed dashboard domain |
| `homelab.services.akkudoktorEos.dataDir` | string | `/var/lib/akkudoktor-eos` | Persistent data directory |

Production wiring:

```nix
homelab.services.akkudoktorEos = {
  enable = true;
  domain = "eos.frame1.hobitin.eu";
};
```

## Access

- Dashboard: `https://eos.frame1.hobitin.eu`
- Internal API: `127.0.0.1:8503`
- Internal dashboard: `127.0.0.1:8504`
- Systemd service: `podman-akkudoktor-eos.service`
- State directory: `/var/lib/akkudoktor-eos`

The API and dashboard bind only to localhost on the host. Caddy exposes the dashboard over HTTPS.

## Control Boundary

EOS is deployed as an optimizer only. It does not publish MQTT commands, call evcc, call Home Assistant services, or directly control chargers, batteries, or other physical devices.

The first rollout treats optimizer output as advisory. EOS Connect is the planned caller that can turn current state and forecasts into displayed plans.

## Troubleshooting

```bash
systemctl status podman-akkudoktor-eos
journalctl -u podman-akkudoktor-eos -n 200 --no-pager
ss -ltnp | egrep ':8503|:8504'
```

## Dependencies

- Podman / NixOS OCI containers
- Caddy for HTTPS routing

## Links

- [Akkudoktor EOS](https://github.com/Akkudoktor-EOS/EOS)
