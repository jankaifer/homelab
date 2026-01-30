# Ticket 005: Add Grafana Module

**Status**: DONE
**Created**: 2026-01-29
**Updated**: 2026-01-30

## Task

Create a Grafana module for dashboards and visualization following the established module pattern (`homelab.services.grafana.enable`).

Grafana will:
- Provide dashboards for Prometheus metrics
- Provide log exploration via Loki
- Serve as the main observability UI

## Implementation Plan

1. Create `modules/services/grafana.nix` with:
   - Port 3001 (default, since Homepage uses 3000)
   - Domain `grafana.lan.kaifer.dev`
   - Auto-provision VictoriaMetrics and Loki data sources
   - Hardcoded admin password for VM testing (agenix later per ticket 006)
   - No pre-provisioned dashboards for now
2. Create documentation at `docs/services/grafana.md`
3. Update server config to import and enable Grafana
4. Update `docs/OVERVIEW.md`

## Dependencies

- Ticket 001 (VM workflow) - DONE
- Ticket 003 (VictoriaMetrics) - DONE
- Ticket 004 (Loki) - DONE

## Work Log

### 2026-01-29

- Ticket created
- Homepage module already references Grafana at :3001
- Awaiting planning discussion with user

### 2026-01-30

- Clarified requirements with user:
  - Port: 3001 (since Homepage uses 3000)
  - Domain: grafana.lan.kaifer.dev
  - Data sources: VictoriaMetrics + Loki (auto-provisioned)
  - Admin password: hardcoded "admin" for now, agenix later
  - Dashboards: none pre-provisioned for now
- Created `modules/services/grafana.nix`:
  - Configurable port (default 3001), domain, adminPassword
  - Auto-provisions VictoriaMetrics as default Prometheus data source
  - Auto-provisions Loki as logs data source
  - Registers with Caddy reverse proxy
  - Registers with Homepage dashboard
- Created `docs/services/grafana.md` with configuration docs
- Updated `machines/server/default.nix` to import and enable Grafana
- Updated `docs/OVERVIEW.md` with Grafana in architecture diagram and service list
- Tested in VM:
  - `nix eval` validation passed
  - VM build and boot successful
  - Grafana health check: OK (version 12.3.1)
  - Both data sources provisioned correctly
  - Homepage still working
