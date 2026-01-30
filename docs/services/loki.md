# Loki

Log storage and query engine. Designed to be cost effective and easy to operate.

## Status

**Enabled** - Active in server configuration

## Configuration

```nix
homelab.services.loki = {
  enable = true;
  # port = 3100;              # HTTP API port
  # retentionPeriod = "360h"; # 15 days
  # domain = "logs.lan.kaifer.dev";
};
```

## Access

- **Metrics**: https://logs.lan.kaifer.dev:8443/metrics (via Caddy)
- **Health**: https://logs.lan.kaifer.dev:8443/ready
- **API**: https://logs.lan.kaifer.dev:8443/loki/api/v1/...

Note: Loki has no built-in web UI. Use Grafana to explore logs.

## Architecture

```
systemd journal → Alloy → Loki → Grafana
                 (ships)  (stores) (queries)
```

Log collection is handled by [Alloy](alloy.md), not Loki itself.

## Storage

- **Location**: `/var/lib/loki/`
- **Retention**: 15 days (configurable via `retentionPeriod`)
- **Backend**: Local filesystem with TSDB index

## Querying Logs

Example LogQL queries (use in Grafana Explore):

```logql
# All logs from a specific unit
{unit="caddy.service"}

# Error logs only
{job="systemd-journal"} |= "error"

# Filter by log level
{level="err"}

# Logs from last hour with rate
rate({unit="grafana.service"}[1h])
```

## Dependencies

- Caddy reverse proxy (for HTTPS access)
- Alloy (for log collection)
- Grafana (for log exploration UI)

## Upstream Documentation

- [Grafana Loki](https://grafana.com/docs/loki/latest/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
