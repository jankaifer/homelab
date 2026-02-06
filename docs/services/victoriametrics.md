# VictoriaMetrics

VictoriaMetrics is a fast, cost-effective time-series database. It's a drop-in replacement for Prometheus with better resource efficiency (lower RAM, CPU, and disk usage).

## Status

**Enabled** in server configuration.

## Configuration

**Module:** `modules/services/victoriametrics.nix`
**Pattern:** `homelab.services.victoriametrics.enable`

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `homelab.services.victoriametrics.enable` | `false` | Enable VictoriaMetrics |
| `homelab.services.victoriametrics.port` | `8428` | Internal port for VictoriaMetrics |
| `homelab.services.victoriametrics.retentionPeriod` | `"15d"` | How long to retain metrics (e.g., 15d, 1w, 1y) |
| `homelab.services.victoriametrics.nodeExporter.enable` | `true` | Enable node_exporter for system metrics |
| `homelab.services.victoriametrics.domain` | `metrics.local.hobitin.eu` | Domain for web UI (via Caddy) |

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

- **Web UI**: https://metrics.local.hobitin.eu (via Caddy reverse proxy)
- **VM Testing**: https://metrics.local.hobitin.eu:8443
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

## Links

- [VictoriaMetrics Docs](https://docs.victoriametrics.com/)
- [NixOS VictoriaMetrics Module](https://search.nixos.org/options?channel=unstable&query=services.victoriametrics)
