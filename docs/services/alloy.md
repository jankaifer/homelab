# Alloy

Grafana's unified telemetry collector for logs, metrics, and traces.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/alloy.nix`
**Pattern:** `homelab.services.alloy.enable`

**Options:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.alloy.enable` | bool | false | Enable Alloy |
| `homelab.services.alloy.port` | int | 12345 | HTTP endpoint for metrics/health |
| `homelab.services.alloy.logs.enable` | bool | true | Ship systemd journal logs to Loki |

**Current configuration:**
```nix
homelab.services.alloy = {
  enable = true;
  # port = 12345;      # HTTP server port (metrics/health)
  # logs.enable = true; # Ship systemd journal to Loki
};
```

## Purpose

Alloy is a single agent that can collect and ship:
- **Logs** → Loki (currently enabled)
- **Metrics** → VictoriaMetrics (future)
- **Traces** → Tempo (future)

## Current Features

### Log Collection
- Reads systemd journal
- Ships to Loki with labels:
  - `job`: systemd-journal
  - `host`: hostname
  - `unit`: systemd unit name
  - `hostname`: hostname
  - `level`: log priority

## Access

Alloy has no web UI. Monitor via:
- **Grafana**: Check Loki data source for logs
- **Metrics endpoint**: `http://127.0.0.1:12345/metrics` (scraped by VictoriaMetrics)

## Files

- `modules/services/alloy.nix` - NixOS module definition

## Dependencies

- Loki (for log storage, when `logs.enable = true`)
- VictoriaMetrics (for Alloy's own metrics)

## Future Plans

- Metrics collection (replace/complement node_exporter)
- Trace collection (when Tempo is added)
- Application metrics via OpenTelemetry

## Links

- [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [Alloy Components](https://grafana.com/docs/alloy/latest/reference/components/)
