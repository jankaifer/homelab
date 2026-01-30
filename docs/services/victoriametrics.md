# VictoriaMetrics

VictoriaMetrics is a fast, cost-effective time-series database. It's a drop-in replacement for Prometheus with better resource efficiency (lower RAM, CPU, and disk usage).

## Status

**Enabled** in server configuration.

## Configuration

Module: `modules/services/victoriametrics.nix`
Pattern: `homelab.services.victoriametrics.enable`

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable VictoriaMetrics |
| `port` | `8428` | Internal port for VictoriaMetrics |
| `retentionPeriod` | `"15d"` | How long to retain metrics (e.g., 15d, 1w, 1y) |
| `nodeExporter.enable` | `true` | Enable node_exporter for system metrics |
| `domain` | `metrics.lan.kaifer.dev` | Domain for web UI (via Caddy) |

### Decentralized Scrape Config

Services register their own scrape targets via `homelab.prometheus.scrapeConfigs` (Prometheus-compatible format):

```nix
# Example: in your service module
homelab.prometheus.scrapeConfigs = [
  {
    job_name = "my-service";
    static_configs = [{
      targets = [ "localhost:9100" ];
      labels = { instance = config.networking.hostName; };
    }];
  }
];
```

## Access

- **Web UI**: https://metrics.lan.kaifer.dev (via Caddy reverse proxy)
- **VM Testing**: https://metrics.lan.kaifer.dev:8443
- **vmui**: Web UI at `/vmui` path for exploring metrics

## Exporters

Currently enabled:
- **node_exporter** (port 9100) - System metrics (CPU, memory, disk, network)
- **Caddy metrics** (port 2019) - Web server metrics

## Prometheus Compatibility

VictoriaMetrics is fully compatible with:
- Prometheus scrape config format
- PromQL query language
- Grafana (use Prometheus data source type)
- All Prometheus exporters

## Dependencies

- Caddy (reverse proxy)
- Homepage (dashboard entry auto-registered)

## Upstream Documentation

- [VictoriaMetrics Docs](https://docs.victoriametrics.com/)
- [NixOS VictoriaMetrics Module](https://search.nixos.org/options?channel=unstable&query=services.victoriametrics)
