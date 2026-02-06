# Loki

Log storage and query engine. Designed to be cost effective and easy to operate.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/loki.nix`
**Pattern:** `homelab.services.loki.enable`

**Options:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.loki.enable` | bool | false | Enable Loki |
| `homelab.services.loki.port` | int | 3100 | Loki HTTP API port |
| `homelab.services.loki.retentionPeriod` | string | `360h` | Log retention window |
| `homelab.services.loki.domain` | string | `logs.local.hobitin.eu` | External domain via Caddy |

**Current configuration:**
```nix
homelab.services.loki = {
  enable = true;
  # port = 3100;              # HTTP API port
  # retentionPeriod = "360h"; # 15 days
  # domain = "logs.local.hobitin.eu";
};
```

## Access

- **VM (local):** https://logs.local.hobitin.eu:8443/ready
- **Production:** https://logs.local.hobitin.eu/ready
- **API:** `https://logs.local.hobitin.eu/loki/api/v1/...`
- **Metrics:** `https://logs.local.hobitin.eu/metrics`

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

## Links

- [Grafana Loki](https://grafana.com/docs/loki/latest/)
- [LogQL](https://grafana.com/docs/loki/latest/query/)
