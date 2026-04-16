# Ticket 030: Energy UI Scenario Switcher

**Status**: DONE
**Created**: 2026-04-16
**Updated**: 2026-04-16

## Task

Add one real plan source plus prepared fake seasonal scenarios so the UI can switch between live runtime data and curated demos when the live plan is not interesting.

## Implementation Plan

- Add a scenario catalog with one live source and four seasonal demo sources
- Extend the UI backend so `/api/live/*` can serve either the real plan or a simulated seasonal plan
- Add a scenario picker to the UI and make fake scenarios read-only for Tesla calendar edits
- Cover the scenario API with tests and update service docs

## Work Log

### 2026-04-16

- Added `real`, `winter`, `spring`, `summer`, and `autumn` scenario sources
- Implemented backend scenario selection using the live planner for `real` and planner simulation for seasonal demos
- Added a UI source switcher, fake-scenario banner, and Tesla calendar read-only state for synthetic scenarios
- Added API tests for scenario listing and fake-plan retrieval
