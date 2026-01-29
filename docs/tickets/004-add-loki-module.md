# Ticket 004: Add Loki Module

**Status**: PLANNING
**Created**: 2026-01-29
**Updated**: 2026-01-29

## Task

Create a Loki module for log aggregation following the established module pattern (`homelab.services.loki.enable`).

Loki will:
- Aggregate logs from all services
- Integrate with Grafana for log exploration
- Work alongside Prometheus for full observability

## Implementation Plan

[To be discussed]

## Open Questions

- Use promtail or systemd journal integration for log shipping?
- What retention period for logs?
- Storage backend - local filesystem sufficient for homelab?
- What port for Loki API? (default 3100)

## Dependencies

- Ticket 001 (VM workflow) should be verified first
- Nice to have Ticket 003 (Prometheus) done first for full observability stack

## Work Log

### 2026-01-29

- Ticket created
- Awaiting planning discussion with user
