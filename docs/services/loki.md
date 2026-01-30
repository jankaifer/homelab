# Loki

Log aggregation system designed to be cost effective and easy to operate.

## Status

**Enabled** - Active in server configuration

## Configuration

```nix
homelab.services.loki = {
  enable = true;
  # port = 3100;              # Loki HTTP API port
  # retentionPeriod = "360h"; # 15 days
  # domain = "logs.lan.kaifer.dev";

  # alloy = {
  #   enable = true;          # Ship systemd journal logs (default)
  #   port = 12345;           # Alloy metrics port
  # };
};
```

## Access

- **Metrics**: https://logs.lan.kaifer.dev:8443/metrics (via Caddy)
- **Health**: https://logs.lan.kaifer.dev:8443/ready
- **API**: https://logs.lan.kaifer.dev:8443/loki/api/v1/...

Note: Loki has no built-in web UI. Use Grafana to explore logs.

## Components

### Loki Server
- Receives and stores logs
- Provides LogQL query API
- Uses local filesystem storage (TSDB)

### Grafana Alloy
- Grafana's newer log collector (replaces Promtail)
- Collects logs from systemd journal
- Ships to Loki with labels:
  - `job`: systemd-journal
  - `host`: hostname
  - `unit`: systemd unit name
  - `hostname`: hostname
  - `level`: log priority (info, warning, err, etc.)

## Storage

- **Location**: `/var/lib/loki/`
- **Retention**: 15 days (configurable via `retentionPeriod`)
- **Backend**: Local filesystem with TSDB index

## Integration

### Homepage Dashboard
Automatically registered in the Monitoring category.

### Grafana
Automatically configured as a data source when both services are enabled.

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
- Homepage (for dashboard registration)
- Grafana (for log exploration UI)

## Upstream Documentation

- [Grafana Loki](https://grafana.com/docs/loki/latest/)
- [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
