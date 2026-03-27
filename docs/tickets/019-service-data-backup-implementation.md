# Ticket 019: Service Data Backup Implementation

**Status**: IN_PROGRESS
**Created**: 2026-03-27
**Updated**: 2026-03-27

## Task

Implement backups for the service data that should be protected under the homelab backup policy. This ticket depends on Ticket 018 defining what must be backed up, where it should go, and how restores are expected to work.

## Implementation Plan

1. Implement backups with `services.restic.backups`
2. Add agenix-managed restic repository/password secrets
3. Back up Tier-1 service state and host recovery state
4. Add selective Home Assistant stop/start hooks around backups
5. Validate a real backup and restore after repository credentials are filled in

## Expected Initial Scope

- Home Assistant state and configuration
- Zigbee2MQTT data
- VictoriaMetrics data
- Grafana state
- Tailscale state and SSH host keys

## Dependencies

- Ticket 018: Backup policy and restore runbook

## Work Log

### 2026-03-27

- Ticket created from roadmap work selection.
- Scoped as implementation-only so policy and restore design stay separate from mechanics.
- Added `modules/services/backup.nix` and enabled it on `frame1`.
- Wired `services.restic.backups.frame1` to object-storage credentials via agenix.
- Added placeholder secrets and an example repository environment file format.
- Configured retention to 30 daily / 12 monthly / 100 yearly snapshots as the practical restic equivalent of long-lived yearly retention.
- Added selective Home Assistant stop/start hooks around the backup window.
- Remaining work: fill in real repository credentials and execute a real backup plus restore validation.
