# Ticket 019: Service Data Backup Implementation

**Status**: DONE
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
- Replaced the placeholder restic credentials with a real Backblaze B2 S3 repository:
  - bucket: `jankaifer-frame1-backup`
  - prefix: `frame1`
  - endpoint: `s3.eu-central-003.backblazeb2.com`
- Deployed the updated configuration to `frame1` with `deploy-rs`.
- Ran the first real backup via `systemctl start restic-backups-frame1.service`.
- Restic initialized the repository and saved the first snapshot as `49a3c261`.
- Verified post-backup repository health with the built-in `restic check` run; no errors were reported.
- Ran a real restore test into `/restore-test` on `frame1`:
  - restored `/var/lib/zigbee2mqtt`
  - verified `configuration.yaml`, `coordinator_backup.json`, `database.db`, and `state.json`
- Observed one follow-up item: `restic snapshots` printed stale lock-object warnings (`Load(<lock/...>) failed: Key not found`) before successfully listing snapshots. The backup and restore still succeeded, so this is tracked as an operational note rather than a blocker.
