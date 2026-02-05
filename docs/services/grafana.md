# Grafana

Dashboards and visualization for metrics and logs.

## Status

**Enabled** - Active in server configuration

## Configuration

```nix
homelab.services.grafana = {
  enable = true;
  # port = 3001;                         # Web UI port
  # domain = "grafana.local.kaifer.dev";   # Access domain

  # For VM testing:
  adminPassword = "admin";

  # For production (with agenix):
  # adminPasswordFile = config.age.secrets.grafana-admin-password.path;
};
```

## Access

- **Web UI**: https://grafana.local.kaifer.dev:8443
- **Default login**: admin / admin

## Data Sources

Automatically provisioned when the corresponding services are enabled:

| Data Source | Type | URL |
|-------------|------|-----|
| VictoriaMetrics | Prometheus | http://127.0.0.1:8428 |
| Loki | Loki | http://127.0.0.1:3100 |

## Features

- **Metrics exploration**: Query VictoriaMetrics using PromQL
- **Log exploration**: Query Loki using LogQL
- **Dashboards**: Create and share dashboards
- **Alerts**: Configure alerting rules (future)

## Storage

- **Location**: `/var/lib/grafana/`
- **Database**: SQLite (default)

## Dependencies

- Caddy reverse proxy (for HTTPS access)
- Homepage (for dashboard registration)
- VictoriaMetrics (metrics data source)
- Loki (logs data source)

## Upstream Documentation

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
