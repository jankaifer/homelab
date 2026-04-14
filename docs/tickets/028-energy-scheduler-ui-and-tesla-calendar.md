# Ticket 028: Energy Scheduler UI and Tesla Calendar

**Status**: DONE
**Created**: 2026-04-14
**Updated**: 2026-04-14

## Task

Add an internal UI for the energy scheduler that explains the current plan, exposes Tesla departure planning for the next 14 days, and provides a small preset-only simulation surface.

## Implementation Plan

1. Extend the scheduler runtime state with richer explainability outputs
2. Add a Tesla 14-day planning calendar with explicit/default/no-departure semantics
3. Add a separate UI service behind Caddy and Homepage
4. Add tests for calendar semantics and the UI API

## Work Log

### 2026-04-14

- Added `src/energy_scheduler/calendar.py` for Tesla calendar storage, validation, default generation, and demand-scenario derivation
- Extended demand bands with UI-oriented metadata such as display name and confidence source
- Refactored the config-backed demand adapter to generate Tesla demand bands from the shared runtime calendar
- Extended the scheduler snapshot output with:
  - summary cards
  - telemetry timeline
  - decision cards
  - band summaries
  - scenario summaries
  - Tesla calendar summaries
- Added `src/energy_scheduler/ui.py` to serve the explainability UI and JSON API from a separate Python service
- Added repo-defined simulation presets under `src/energy_scheduler/presets.py`
- Added `modules/services/energy-scheduler-ui.nix` and wired it into the machine imports
- Updated service documentation and overview docs for the new UI surface
- Added tests for:
  - default / explicit / no-departure Tesla calendar semantics
  - UI calendar GET/PUT behavior

## Validation Notes

- Passed:
  - `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
  - `nix develop -c sh -lc 'PYTHONPATH=src python -m unittest discover -s tests/energy_scheduler -v'`
