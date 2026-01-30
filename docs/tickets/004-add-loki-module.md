# Ticket 004: Add Loki Module

**Status**: DONE
**Created**: 2026-01-29
**Updated**: 2026-01-30

## Task

Create a Loki module for log aggregation following the established module pattern (`homelab.services.loki.enable`).

Loki will:
- Aggregate logs from all services
- Integrate with Grafana for log exploration
- Work alongside Prometheus for full observability

## Implementation Plan

1. Create `modules/services/loki.nix` with:
   - Loki server configuration (port 3100, filesystem storage, TSDB index)
   - Promtail for shipping systemd journal logs
   - 15-day retention (360h)
   - Caddy integration at logs.lan.kaifer.dev
   - Homepage registration

2. Enable in server config
3. Create documentation at `docs/services/loki.md`
4. Update `docs/OVERVIEW.md`

## Decisions

- **Log shipping**: Promtail - standard companion, good systemd journal integration
- **Retention**: 15 days (360h) - matches VictoriaMetrics
- **Storage**: Local filesystem with TSDB - sufficient for homelab
- **Port**: 3100 (Loki default)

## Work Log

### 2026-01-29

- Ticket created
- Awaiting planning discussion with user

### 2026-01-30

- Implemented Loki module with Promtail
- Added to server config and enabled
- Created service documentation
- Updated OVERVIEW.md with architecture diagram and service listing
- Config validates successfully
