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
| `homelab.services.akkudoktorEos.settings` | attrs | `{}` | EOS config written to `/data/config/EOS.config.json` |

Production wiring:

```nix
homelab.services.akkudoktorEos = {
  enable = true;
  domain = "eos.frame1.hobitin.eu";
  settings = {
    general.timezone = "Europe/Prague";
    ems.mode = "PREDICTION";
    elecprice.provider = "ElecPriceEnergyCharts";
    elecprice.energycharts.bidding_zone = "CZ";
    pvforecast.provider = "PVForecastAkkudoktor";
    weather.provider = "OpenMeteo";
    load.provider = "LoadAkkudoktor";
    feedintariff.provider = "FeedInTariffFixed";
  };
};
```

`frame1` currently uses Prague-area coordinates, an aggregate 12.87 kWp
near-south-facing PV plane, a 14 kWh Pylontech battery behind the Victron
MultiPlus-II stack, one 75 kWh Tesla Model 3, and a 3000 kWh/year baseline load
so EOSdash has prediction data for the advisory Plan and Prediction pages. The
PV plane is configured at azimuth `179.0` instead of exact south because EOS
translates exact south to Akkudoktor API `azimuth=0`, which the upstream forecast
API currently rejects. Replace the aggregate PV geometry with exact per-plane
site geometry when available.

Live state is mirrored one-way from evcc into EOS measurements by
`eos-evcc-readonly-measurements.timer`. The timer reads evcc's local
`/api/state` endpoint and writes only EOS measurement values for battery SoC,
battery power, Tesla SoC, and Tesla charge power. It does not call evcc command
endpoints, publish MQTT commands, or control the charger.

## Access

- Dashboard: `https://eos.frame1.hobitin.eu`
- Internal API: `127.0.0.1:8503`
- Internal dashboard: `127.0.0.1:8504`
- Systemd service: `podman-akkudoktor-eos.service`
- State directory: `/var/lib/akkudoktor-eos`
- Config file: `/var/lib/akkudoktor-eos/config/EOS.config.json`

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
systemctl status eos-evcc-readonly-measurements.timer
journalctl -u podman-akkudoktor-eos -n 200 --no-pager
journalctl -u eos-evcc-readonly-measurements -n 100 --no-pager
ss -ltnp | egrep ':8503|:8504'
stat -c '%u:%g %a %n' /var/lib/akkudoktor-eos
curl -s http://127.0.0.1:8503/v1/prediction/keys
curl -s http://127.0.0.1:8503/v1/measurement/keys
```

## Dependencies

- Podman / NixOS OCI containers
- Caddy for HTTPS routing

## Links

- [Akkudoktor EOS](https://github.com/Akkudoktor-EOS/EOS)
