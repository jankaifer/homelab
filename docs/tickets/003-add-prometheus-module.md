# Ticket 003: Add Metrics Collection Module

**Status**: DONE
**Created**: 2026-01-29
**Updated**: 2026-01-30

## Task

Create a metrics collection module following the established module pattern.

Originally planned for Prometheus, switched to VictoriaMetrics (more efficient, Prometheus-compatible).

VictoriaMetrics will:
- Collect system metrics (node_exporter)
- Scrape metrics from other services
- Store time-series data for Grafana dashboards

## Implementation Plan

### Phase 1: DNS Setup
- Add `*.lan.kaifer.dev` CNAME record → `lan.kaifer.dev` in Cloudflare

### Phase 2: Caddy Wildcard & Service Registration
- Update Caddy module to request wildcard cert for `*.lan.kaifer.dev`
- Create `homelab.caddy.virtualHosts` option for services to register reverse proxies
- Each service module adds its own virtualHost entry
- Homepage stays at `lan.kaifer.dev`, other services get subdomains

### Phase 3: Prometheus Module
- Create `modules/services/prometheus.nix`
- Create `homelab.prometheus.scrapeConfigs` option for decentralized registration
- Enable node_exporter by default
- 15-day retention
- Register `prometheus.lan.kaifer.dev` virtualHost with Caddy
- Register own scrape target

### Phase 4: Service Integration
- Update Caddy module to expose metrics and register scrape target
- Pattern established for future services (Loki, Grafana, etc.)

## Decisions Made

- **Wildcard DNS**: `*.lan.kaifer.dev` CNAME to `lan.kaifer.dev`
- **Subdomains**: Each service gets `<service>.lan.kaifer.dev`
- **Decentralized config**: Services register their own scrape targets and reverse proxy entries
- **Retention**: 15 days (default)
- **Port**: 9090 (internal), accessible via Caddy reverse proxy

## Dependencies

- Ticket 001 (VM workflow) - DONE
- Ticket 002 (Caddy) - DONE

## Work Log

### 2026-01-29

- Ticket created
- Awaiting planning discussion with user

### 2026-01-30

- Planning discussion with user
- Decided on wildcard subdomain approach
- Decided on decentralized scrape target registration (each module registers itself)
- Starting implementation
- Created `modules/services/prometheus.nix`:
  - `homelab.services.prometheus.enable` with options for port, retention, nodeExporter
  - `homelab.prometheus.scrapeConfigs` shared option for decentralized scrape target registration
  - node_exporter enabled by default (port 9100)
  - Registers its own virtualHost `prometheus.lan.kaifer.dev`
- Updated Caddy module:
  - Added `metrics.enable` option (default true)
  - Enabled Caddy metrics endpoint for Prometheus scraping
  - Caddy registers its own scrape config
- Updated server config to enable Prometheus
- Updated Homepage to show Prometheus and Grafana in dashboard
- Updated documentation: prometheus.md, OVERVIEW.md
- Config validates successfully
- **TODO**: User needs to add wildcard DNS `*.lan.kaifer.dev` CNAME → `lan.kaifer.dev` in Cloudflare
- VM build completed successfully
- **PIVOT**: Switched from Prometheus to VictoriaMetrics (user preference)
  - More resource efficient (RAM, CPU, disk)
  - Drop-in replacement, same scrape config format
  - Same PromQL query language
  - Compatible with Grafana
- Renamed module to `victoriametrics.nix`
- Changed domain from `prometheus.lan.kaifer.dev` to `metrics.lan.kaifer.dev`
- Updated all documentation
- Added wildcard DNS record `*.lan.kaifer.dev` CNAME → `lan.kaifer.dev` via Cloudflare API
- VM tested successfully:
  - VictoriaMetrics UI accessible at https://metrics.lan.kaifer.dev:8443
  - Both scrape targets up: node (system metrics), caddy (web server metrics)
  - Decentralized scrape config pattern working

## Summary

VictoriaMetrics is now enabled as the metrics collection backend. It uses the same Prometheus scrape config format, so services register their own scrape targets via `homelab.prometheus.scrapeConfigs`. Currently scraping node_exporter (system metrics) and Caddy (web server metrics). Accessible at https://metrics.lan.kaifer.dev via Caddy reverse proxy.
