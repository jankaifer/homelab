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
| `homelab.services.akkudoktorEos.dataUid` | int | 100 | Numeric UID of the EOS user inside the container |
| `homelab.services.akkudoktorEos.dataGid` | int | 101 | Numeric GID of the EOS group inside the container |
| `homelab.services.akkudoktorEos.extraEnvironment` | attrs | `{}` | Extra EOS environment variables |

Production wiring:

```nix
homelab.services.akkudoktorEos = {
  enable = true;
  domain = "eos.frame1.hobitin.eu";
  extraEnvironment = {
    EOS_GENERAL__TIMEZONE = "Europe/Prague";
    EOS_EMS__MODE = "PREDICTION";
    EOS_ELECPRICE__PROVIDER = "ElecPriceEnergyCharts";
    EOS_ELECPRICE__ENERGYCHARTS__BIDDING_ZONE = "CZ";
    EOS_PVFORECAST__PROVIDER = "PVForecastAkkudoktor";
    EOS_WEATHER__PROVIDER = "OpenMeteo";
    EOS_LOAD__PROVIDER = "LoadAkkudoktor";
    EOS_FEEDINTARIFF__PROVIDER = "FeedInTariffFixed";
  };
};
```

`frame1` currently uses Prague-area coordinates, one 5 kWp south-facing PV plane,
and a 3000 kWh/year baseline load so EOSdash has prediction data for the
advisory Plan and Prediction pages. Replace those values with exact site
geometry and annual load when available.

## Access

- Dashboard: `https://eos.frame1.hobitin.eu`
- Internal API: `127.0.0.1:8503`
- Internal dashboard: `127.0.0.1:8504`
- Systemd service: `podman-akkudoktor-eos.service`
- State directory: `/var/lib/akkudoktor-eos`

The API and dashboard bind only to localhost on the host. Caddy exposes the dashboard over HTTPS.
The state directory is owned by the EOS container user (`100:101`) because the
service drops privileges for dashboard and optimizer work and writes measurement
and cache files under `/data`.

## Control Boundary

EOS is deployed as an optimizer only. It does not publish MQTT commands, call evcc, call Home Assistant services, or directly control chargers, batteries, or other physical devices.

The first rollout treats optimizer output as advisory. EOS Connect is the planned caller that can turn current state and forecasts into displayed plans.

## Troubleshooting

```bash
systemctl status podman-akkudoktor-eos
journalctl -u podman-akkudoktor-eos -n 200 --no-pager
ss -ltnp | egrep ':8503|:8504'
stat -c '%u:%g %a %n' /var/lib/akkudoktor-eos
curl -s http://127.0.0.1:8503/v1/prediction/keys
```

## Dependencies

- Podman / NixOS OCI containers
- Caddy for HTTPS routing

## Links

- [Akkudoktor EOS](https://github.com/Akkudoktor-EOS/EOS)
