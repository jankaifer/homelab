# Ticket 032: Energy UI Bun Dashboard

**Status**: DONE
**Created**: 2026-04-25
**Updated**: 2026-04-25

## Task

Replace the editable energy scheduler UI with a read-only dashboard that uses a Bun backend, a simple React client, and shared TypeScript types across client and server.

## Implementation Plan

1. Keep the existing Python/PuLP scheduler as the optimization engine.
2. Add a Bun API server that reads `latest-plan.json` and `history/*.json`.
3. Add shared TypeScript snapshot/dashboard types used by both server and React client.
4. Replace workbench/scenario-editing UI with a single date-scoped dashboard for future plan data and historical runs.
5. Package the UI service as a Bun executable in Nix.

## Work Log

### 2026-04-25

- Added a Bun server for read-only dashboard APIs.
- Added a React dashboard bundle with shared client/server types.
- Reworked the NixOS UI module to run the Bun service instead of the Python UI entry point.
- Updated docs and local demo/browser-check scripts for the simplified dashboard.
