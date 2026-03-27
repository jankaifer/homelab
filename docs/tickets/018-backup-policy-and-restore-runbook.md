# Ticket 018: Backup Policy and Restore Runbook

**Status**: DONE
**Created**: 2026-03-27
**Updated**: 2026-03-27

## Task

Define the homelab backup policy in concrete terms and document a restore runbook that can be executed under stress. The goal is to turn the existing "backup by default" direction into an explicit service-by-service policy with restore expectations, retention, and validation steps.

## Implementation Plan

1. Inventory persistent data on `frame1` by service and host path
2. Classify each dataset into Tier-1 or Tier-2 from the project plan
3. Define backup targets, retention, encryption, and offsite expectations
4. Document restore procedures for the highest-value services first
5. Add a recurring validation checklist for restore testing

## Work Log

### 2026-03-27

- Ticket created from roadmap work selection.
- Scope intentionally starts with policy and runbook before implementation so later automation has a clear contract.
- Locked the backup policy around encrypted object-storage restic backups with nightly cadence.
- Classified Tier-1 and rebuildable datasets and documented them in `docs/services/backup.md`.
- Added service-level restore runbooks for Home Assistant and Zigbee2MQTT.
- Defined the real restore-test target as a restore into a scratch path on `frame1`.
