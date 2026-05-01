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
| `homelab.services.grafana.domain` | string | `grafana.local.hobitin.eu` | External domain via Caddy; production overrides this to `grafana.frame1.hobitin.eu` |
| `homelab.services.grafana.adminPassword` | string or null | `admin` | Admin password for local/VM testing |
| `homelab.services.grafana.adminPasswordFile` | string or null | null | File path for production secret (agenix) |
| `homelab.services.grafana.oidc.enable` | bool | false | Enable Authelia OIDC login |
| `homelab.services.grafana.oidc.issuerUrl` | string | `https://auth.frame1.hobitin.eu` | Authelia issuer URL |
| `homelab.services.grafana.oidc.clientId` | string | `grafana` | OIDC client ID |
| `homelab.services.grafana.oidc.clientSecretFile` | string or null | null | agenix-managed OIDC client secret |
| `homelab.services.grafana.oidc.roleAttributePath` | string | group mapping | JMESPath role mapping from Authelia groups |

**Current configuration:**
```nix
homelab.services.grafana = {
  enable = true;
  # port = 3001;
  domain = "grafana.frame1.hobitin.eu";
  adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  oidc = {
    enable = true;
    issuerUrl = "https://auth.frame1.hobitin.eu";
    clientSecretFile = config.age.secrets.grafana-oidc-client-secret.path;
  };
};
```

## Access

| Environment | URL |
|-------------|-----|
| VM (local) | https://grafana.local.hobitin.eu:8443 |
| Production | https://grafana.frame1.hobitin.eu |

- **Login:** Authelia OIDC or local `admin` break-glass account
- **Admin password:** `secrets/grafana-admin-password.age`

## Authelia OIDC

Grafana uses Authelia's native OIDC provider rather than only reverse-proxy auth, so Grafana can see user identity and map groups to roles.

Role mapping:

| Authelia group | Grafana role |
|----------------|--------------|
| `admins` | Admin |
| `grafana-editors` | Editor |
| all other authenticated users | Viewer |

Local login remains enabled with the `admin` account for recovery if Authelia is unavailable.

## Data Sources

Automatically provisioned when the corresponding services are enabled:

| Data Source | Type | URL |
|-------------|------|-----|
| VictoriaMetrics | Prometheus | http://127.0.0.1:8428 |
| Loki | Loki | http://127.0.0.1:3100 |

Provisioned datasource UIDs:

- `victoriametrics`
- `loki`

## Features

- **Metrics exploration**: Query VictoriaMetrics using PromQL
- **Log exploration**: Query Loki using LogQL
- **Dashboards**: Create and share dashboards
- **Provisioned dashboards**: Shared homelab dashboards can be added declaratively by service modules
- **Alerts**: Configure alerting rules (future)

Current provisioned dashboard:

- `Certificate Health`

## Storage

- **Location**: `/var/lib/grafana/`
- **Database**: SQLite (default)

## Dependencies

- Caddy reverse proxy (for HTTPS access)
- Homepage (for dashboard registration)
- VictoriaMetrics (metrics data source)
- Loki (logs data source)
- Authelia (OIDC login)

## Links

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [PromQL](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
