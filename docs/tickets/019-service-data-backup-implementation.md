# Ticket 019: Service Data Backup Implementation

**Status**: PLANNING
**Created**: 2026-03-27
**Updated**: 2026-03-27

## Task

Implement backups for the service data that should be protected under the homelab backup policy. This ticket depends on Ticket 018 defining what must be backed up, where it should go, and how restores are expected to work.

## Implementation Plan

1. Select the backup mechanism and destination based on Ticket 018
2. Add declarative backup jobs for prioritized service data
3. Ensure secrets needed for backup credentials are managed via agenix
4. Add failure visibility through logs, metrics, or alerts
5. Validate that at least one real backup completes successfully

## Expected Initial Scope

- Home Assistant state and configuration
- Zigbee2MQTT data
- Mosquitto configuration and durable state if needed
- Grafana state if local data is worth preserving
- Host-level configuration or exported state needed for recovery

## Dependencies

- Ticket 018: Backup policy and restore runbook

## Work Log

### 2026-03-27

- Ticket created from roadmap work selection.
- Scoped as implementation-only so policy and restore design stay separate from mechanics.
