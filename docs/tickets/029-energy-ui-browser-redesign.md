# Ticket 029: Energy UI Browser Redesign

**Status**: DONE
**Created**: 2026-04-15
**Updated**: 2026-04-15

## Task

Simplify the energy scheduler UI, remove the confusing scenario lab, improve chart readability, and redesign the Tesla planner into a more familiar calendar flow with modal editing.

## Implementation Plan

1. Simplify the information architecture to three pages: Overview, Timeline, Tesla Plan
2. Replace misleading charts with clearer energy-balance and battery-state views
3. Deduplicate demand bands and fix the telemetry snapshot so the energy story is internally consistent
4. Turn the Tesla planner into a calendar with click-to-edit modal interactions
5. Add a repeatable browser-validation script for desktop and mobile captures

## Work Log

### 2026-04-15

- Removed the preset scenario lab from the UI to reduce clutter and confusion
- Reworked the live snapshot builder so:
  - unconditional demand bands resolve correctly across scenarios
  - flexible load is tracked explicitly in the telemetry timeline
  - visible bands are aggregated and deduplicated instead of repeated per scenario
- Replaced the old canvas charts with simpler SVG views:
  - hourly positive/negative energy balance
  - battery SoC versus reserve/emergency thresholds
  - Tesla charging over the next 24 hours
- Redesigned the Tesla page around a two-week calendar layout with click-to-edit modal interactions
- Added automatic rolling-window refresh for the Tesla 14-day calendar so stale past days do not remain as the “next” plan
- Added `scripts/check-energy-ui-browser.sh` to capture desktop and mobile screenshots through Playwright CLI in a repeatable way
- Updated service docs to reflect the simplified UI surface and browser-validation workflow

## Validation Notes

- Passed:
  - `PYTHONPYCACHEPREFIX=/tmp/energy-pyc python3 -m py_compile src/energy_scheduler/ui.py src/energy_scheduler/service.py src/energy_scheduler/calendar.py`
  - `PYTHONPATH=src python3 -m unittest tests.energy_scheduler.test_calendar -v`
  - `./scripts/check-energy-ui-browser.sh --url http://127.0.0.1:8790/`
- Partial / environment-limited:
  - `uv run pytest tests/energy_scheduler -q` did not work because `pytest` was not installed in the generated environment
  - `uv run python -m unittest discover -s tests/energy_scheduler -v` hit a local `uv`/macOS runtime panic when using the temporary cache path
