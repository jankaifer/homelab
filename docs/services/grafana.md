# Grafana

Dashboards and visualization for metrics and logs.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/grafana.nix`
**Pattern:** `homelab.services.grafana.enable`

**Options:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.grafana.enable` | bool | false | Enable Grafana |
| `homelab.services.grafana.port` | int | 3001 | Internal Grafana HTTP port |
| `homelab.services.grafana.domain` | string | `grafana.local.kaifer.dev` | External domain via Caddy |
| `homelab.services.grafana.adminPassword` | string or null | `admin` | Admin password for local/VM testing |
| `homelab.services.grafana.adminPasswordFile` | string or null | null | File path for production secret (agenix) |

**Current configuration:**
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

| Environment | URL |
|-------------|-----|
| VM (local) | https://grafana.local.kaifer.dev:8443 |
| Production | https://grafana.local.kaifer.dev |

- **Default login (VM/default):** admin / admin

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

## Links

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
