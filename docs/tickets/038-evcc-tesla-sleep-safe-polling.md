# Ticket 038: EVCC Tesla Sleep-Safe Polling

**Status**: DONE
**Created**: 2026-04-27
**Updated**: 2026-04-27

## Task

Reduce EVCC Tesla polling that can wake or keep the Model 3 awake, while
preserving a path to fresh driving SoC when the vehicle is already awake.

## Implementation Plan

- Stop direct Tesla Fleet API polling while the car is disconnected.
- Add optional Tessie credentials support, because EVCC documents Tessie as
  never waking the car and returning cached sleep-state data.
- Document the operational tradeoff and secret format.

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
