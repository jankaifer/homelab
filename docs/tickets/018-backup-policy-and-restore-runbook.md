# Ticket 018: Backup Policy and Restore Runbook

**Status**: PLANNING
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

## Open Questions

- Which cloud or offsite target should be the default for encrypted backups?
- Which datasets are explicitly allowed to remain rebuild-only?
- What restore time objective is acceptable for smart-home services?

## Work Log

### 2026-03-27

- Ticket created from roadmap work selection.
- Scope intentionally starts with policy and runbook before implementation so later automation has a clear contract.
