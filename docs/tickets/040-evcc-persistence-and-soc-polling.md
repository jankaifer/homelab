# Ticket 040: EVCC Persistence and SOC Polling Hardening

**Status**: DONE
**Created**: 2026-05-20
**Updated**: 2026-05-20

## Task

Review EVCC persistence and vehicle polling settings after a report that those
settings may be missing from the repository-managed configuration.

## Implementation Plan

- Keep EVCC state under the existing NixOS `StateDirectory` at `/var/lib/evcc`.
- Pass EVCC an explicit persistent SQLite database path.
- Poll Tesla SoC while the vehicle is connected, using a short interval that can
  catch final SoC after charging stops without polling while unplugged.
- Update EVCC service documentation.

## Work Log

### 2026-05-20

- Confirmed the generated EVCC YAML already contains the Tesla Model 3 vehicle,
  direct Tesla template wiring, and loadpoint SoC polling.
- Confirmed the generated EVCC service did not include an explicit database path.
- Added an explicit `--database /var/lib/evcc/.evcc/evcc.db` service argument
  and reused that path for the admin password helper.
- Changed loadpoint SoC polling to `soc.poll.mode = "connected"` with
  `soc.poll.interval = "5m"` so EVCC polls more often while the car is plugged in
  and can catch final SoC after charging stops, while still avoiding unplugged
  Tesla polling.
