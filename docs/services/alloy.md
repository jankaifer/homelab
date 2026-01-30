# Alloy

Grafana's unified telemetry collector for logs, metrics, and traces.

## Status

**Enabled** - Active in server configuration

## Configuration

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
- **Metrics**: Scraped by VictoriaMetrics at `localhost:12345`

## Dependencies

- Loki (for log storage, when `logs.enable = true`)
- VictoriaMetrics (for Alloy's own metrics)

## Future Plans

- Metrics collection (replace/complement node_exporter)
- Trace collection (when Tempo is added)
- Application metrics via OpenTelemetry

## Upstream Documentation

- [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [Alloy Components](https://grafana.com/docs/alloy/latest/reference/components/)
