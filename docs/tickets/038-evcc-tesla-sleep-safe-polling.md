# Ticket 038: EVCC Tesla Polling Policy

**Status**: DONE
**Created**: 2026-04-27
**Updated**: 2026-04-27

## Task

Decide the EVCC Tesla polling behavior after EVCC warned that always polling can
wake or keep the Model 3 awake.

## Implementation Plan

- Keep the direct Tesla API integration.
- Poll vehicle SoC hourly even when unplugged.
- Document that this intentionally accepts EVCC's polling warning.

## Work Log

### 2026-04-27

- Confirmed production EVCC logs warn about `poll.mode = always` with a 1h
  interval.
- Changed direct Tesla polling to `charging` mode.
- Added optional `secrets/evcc-tessie.env.age` support. When present, frame1
  uses the EVCC `tessie` vehicle template with `poll.mode = always` and a 1m
  interval.
- Validated the direct Tesla and optional Tessie render paths with `nix eval`.
- Built the VM successfully with `./scripts/run-vm-docker.sh --build`.
- Reverted the Tessie path and restored direct Tesla `poll.mode = always` with a
  60m interval by operator preference.
