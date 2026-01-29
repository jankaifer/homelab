# Ticket 003: Add Prometheus Module

**Status**: PLANNING
**Created**: 2026-01-29
**Updated**: 2026-01-29

## Task

Create a Prometheus module for metrics collection following the established module pattern (`homelab.services.prometheus.enable`).

Prometheus will:
- Collect system metrics (node_exporter)
- Scrape metrics from other services
- Store time-series data for Grafana dashboards

## Implementation Plan

[To be discussed]

## Open Questions

- Which exporters to enable by default? (node_exporter is standard)
- What retention period for metrics data?
- Should scrape targets be hardcoded initially or use service discovery?
- What port for Prometheus web UI? (default 9090)

## Dependencies

- Ticket 001 (VM workflow) should be verified first

## Work Log

### 2026-01-29

- Ticket created
- Awaiting planning discussion with user
