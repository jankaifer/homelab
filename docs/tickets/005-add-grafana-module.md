# Ticket 005: Add Grafana Module

**Status**: PLANNING
**Created**: 2026-01-29
**Updated**: 2026-01-29

## Task

Create a Grafana module for dashboards and visualization following the established module pattern (`homelab.services.grafana.enable`).

Grafana will:
- Provide dashboards for Prometheus metrics
- Provide log exploration via Loki
- Serve as the main observability UI

## Implementation Plan

[To be discussed]

## Open Questions

- What port? Homepage already references :3001
- Pre-provision data sources (Prometheus, Loki) declaratively?
- Include any default dashboards? (node exporter dashboard is popular)
- Admin password handling - hardcode for VM testing, agenix for production?

## Dependencies

- Ticket 001 (VM workflow) should be verified first
- Ticket 003 (Prometheus) for metrics data source
- Ticket 004 (Loki) for logs data source

## Work Log

### 2026-01-29

- Ticket created
- Homepage module already references Grafana at :3001
- Awaiting planning discussion with user
