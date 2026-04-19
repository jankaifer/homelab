# Ticket 031: Energy Workbench UI

**Status**: DONE
**Created**: 2026-04-19
**Updated**: 2026-04-20

## Task

Add a named local scenario editor and simulator to the energy scheduler UI so planner inputs can be edited in the browser and run against the same core optimizer without mutating live runtime state.

## Implementation Plan

- Extend the scheduler service and adapters so simulation can run with an explicit `start_at`
- Add a workbench scenario store under the scheduler state directory
- Add workbench CRUD/run API endpoints to the UI backend
- Add a new `Workbench` page with structured editors for prices, solar, battery, base load, Tesla, and generic demand bands
- Persist and display per-scenario run results, assumptions, and shortfall/debug summaries
- Update the UI service module permissions and docs

## Work Log

### 2026-04-19

- Added explicit `start_at` support to the scheduler service simulation path
- Added scenario-local Tesla calendar support in the config adapter and workbench store
- Implemented workbench CRUD/run storage in `src/energy_scheduler/workbench.py`
- Added workbench API methods and routes in `src/energy_scheduler/ui.py`
- Added backend tests covering create/save/clone/run flows

### 2026-04-20

- Implemented the browser workbench page with scenario library, typed editors, reusable series editors, and results/debug output
- Reused the Tesla day modal for both live and workbench-local calendar editing
- Extended the browser regression script to capture the workbench page
- Updated the NixOS UI module so the UI service can write workbench scenarios/results/runtime state
- Updated service docs for the new workbench capabilities and storage layout
