# Backup and Restore

Restic-based encrypted backups for Tier-1 homelab state, with service-level restore runbooks first.

## Status

**Enabled:** Yes on `frame1`, disabled in `frame1-vm`

## Configuration

**Module:** `modules/services/backup.nix`
**Pattern:** `homelab.services.backup.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.backup.enable` | bool | false | Enable Tier-1 restic backups |
| `homelab.services.backup.repositoryEnvFile` | string or null | null | Environment file with `RESTIC_REPOSITORY` and object-store credentials |
| `homelab.services.backup.passwordFile` | string or null | null | Restic repository password file |
| `homelab.services.backup.timer` | string | `daily` | OnCalendar schedule for the backup job |

**Current configuration:**
```nix
homelab.services.backup = {
  enable = true;
  repositoryEnvFile = config.age.secrets.restic-repository-env.path;
  passwordFile = config.age.secrets.restic-password.path;
  # timer = "daily";
};
```

## Policy

### Tier-1 data

- `/var/lib/homeassistant`
- `/var/lib/zigbee2mqtt`
- `/var/lib/victoriametrics`
- `/var/lib/grafana`
- `/var/lib/tailscale`
- `/etc/ssh`

### Lower-tier or rebuildable data

- `/var/lib/loki`
- `/var/lib/acme`
- `/nix`
- Other declarative configuration already tracked in git

### Retention

- `30` daily
- `12` monthly
- `100` yearly snapshots

The plan target was "infinite yearly". Restic only keeps a bounded count, so the module uses `100` yearly snapshots as the practical equivalent for this homelab.

## Runtime Behavior

- Backups run nightly via `services.restic.backups.frame1`
- Restic initializes the repository automatically if it does not exist
- Home Assistant is stopped briefly before backup and started again afterward
- Other services stay online unless a future consistency issue justifies a pause
- Repository checks run after backup with `restic check --read-data-subset=1/20`

## Restore Runbook

### Home Assistant

1. Stop Home Assistant:
   ```bash
   sudo systemctl stop podman-homeassistant
   ```
2. Restore to a staging path:
   ```bash
   sudo restic-frame1 restore latest --target /restore-test --include /var/lib/homeassistant
   ```
3. Validate expected files:
   ```bash
   sudo find /restore-test/var/lib/homeassistant -maxdepth 2 | head
   ```
4. Move validated data into place during a maintenance window if doing a real restore.
5. Start Home Assistant:
   ```bash
   sudo systemctl start podman-homeassistant
   ```

### Zigbee2MQTT

1. Stop Zigbee2MQTT:
   ```bash
   sudo systemctl stop podman-zigbee2mqtt
   ```
2. Restore to a staging path:
   ```bash
   sudo restic-frame1 restore latest --target /restore-test --include /var/lib/zigbee2mqtt
   ```
3. Validate `configuration.yaml` and device database contents before replacing live data.
4. Start Zigbee2MQTT:
   ```bash
   sudo systemctl start podman-zigbee2mqtt
   ```

### Restore Validation Target

The first real restore test should restore Zigbee2MQTT or Home Assistant into a scratch path on `frame1` and confirm the restored files are complete before closing the ticket.

## Secrets

Required secrets:

- `restic-password.age`
- `restic-repository-env.age`

The environment secret should define `RESTIC_REPOSITORY` plus any backend credentials needed by restic, for example S3-compatible credentials.

## Troubleshooting

Run a backup manually:
```bash
sudo systemctl start restic-backups-frame1.service
```

Follow the service logs:
```bash
journalctl -u restic-backups-frame1 -n 200 --no-pager
```

Inspect snapshots:
```bash
sudo restic-frame1 snapshots
```

Check repository health:
```bash
sudo restic-frame1 check --read-data-subset=1/20
```
