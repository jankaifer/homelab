# Ticket 027: Energy Scheduler Foundation

**Status**: DONE
**Created**: 2026-04-10
**Updated**: 2026-04-10

## Task

Implement the first foundation for a local energy scheduler that models solar production, a house battery, and flexible demands under one optimizer.

## Implementation Plan

1. Add a Python scheduler package with a planner, config-backed adapters, and runtime loop
2. Add a NixOS module that packages the application and runs it as a systemd service
3. Document the service and add synthetic tests for the main planner behaviors

## Work Log

### 2026-04-10

- Added the repo-local `energy-scheduler` Python package under `src/energy_scheduler`
- Implemented a piecewise-linear LP planner with:
  - multi-scenario solar forecasts
  - dedicated battery state variables
  - demand bands with per-band value and unmet penalties
  - import/export market pricing
  - best-effort shortfall reporting
- Added config-backed adapters for prices, solar, battery, and demand bands
- Added runtime persistence for latest and historical plans
- Added `modules/services/energy-scheduler.nix` to package and run the daemon as `energy-scheduler.service`
- Added unit tests for:
  - satisfying a required Tesla band when feasible
  - choosing export over low-value pool heating
  - removing import during outage mode

## Validation Notes

- Planned:
  - `python -m unittest discover -s tests`
  - `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
