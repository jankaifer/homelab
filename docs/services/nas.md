# NAS

NAS layout and network file sharing for `frame1`, exposed over SMB and NFS.

## Status

**Enabled:** Yes on `frame1`, disabled in `frame1-vm`

## Configuration

**Module:** `modules/services/nas.nix`
**Pattern:** `homelab.services.nas.enable`

**Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.nas.enable` | bool | false | Enable NAS layout and exports |
| `homelab.services.nas.rootPath` | string | `/nas` | Root path for all NAS shares |
| `homelab.services.nas.lanCidr` | string | `192.168.2.0/24` | Trusted LAN subnet for NFS exports |
| `homelab.services.nas.tailscaleCidr` | string | `100.64.0.0/10` | Trusted Tailscale subnet for NFS exports |
| `homelab.services.nas.adminSmbPasswordFile` | string or null | null | Samba password file for `jankaifer` |
| `homelab.services.nas.guestSmbPasswordFile` | string or null | null | Samba password file for `nasguest` |
| `homelab.services.nas.guestUser` | string | `nasguest` | Guest-style NAS user |
| `homelab.services.nas.sharedGroup` | string | `nas-shared` | Shared media/service group |
| `homelab.services.nas.adminGroup` | string | `nas-admin` | NAS admin-only group |

**Current configuration:**
```nix
homelab.services.nas = {
  enable = true;
  rootPath = "/nas";
  lanCidr = "192.168.2.0/24";
  tailscaleCidr = "100.64.0.0/10";
  adminSmbPasswordFile = config.age.secrets.nas-jankaifer-password.path;
  guestSmbPasswordFile = config.age.secrets.nas-guest-password.path;
};
```

## Tech Stack

- Storage base: existing ext4 root disk on `frame1`
- Network sharing:
  - Samba
  - NFS
- Permissions:
  - Unix users/groups
  - setgid directories
  - no ACLs in v1

## Share Layout

Top-level directories:

- `/nas/media`
- `/nas/downloads`
- `/nas/nvr`
- `/nas/backups`
- `/nas/private`

Library-first media layout:

- `/nas/media/movies`
- `/nas/media/tv`
- `/nas/media/music`
- `/nas/media/books`

Downloads layout:

- `/nas/downloads/complete`
- `/nas/downloads/incomplete`

## Access Model

### Human users

- `jankaifer`
  - admin access
  - full write access to all intended shares
- `nasguest`
  - guest-style human NAS user
  - read-only media access
  - no access to `private`

### Groups

- `nas-admin`
  - admin-only group for private NAS data
- `nas-shared`
  - shared service/media group for future Jellyfin, *arr stack, and related service writes

## Share Permissions

| Share | Intended Use | Access |
|------|--------------|--------|
| `media` | Long-lived library data | `jankaifer` write, `nasguest` read-only, future services via `nas-shared` |
| `downloads` | Disposable downloader staging | `jankaifer` + `nas-shared` write |
| `nvr` | Retention-oriented camera storage | `jankaifer` + `nas-shared` write |
| `backups` | LAN/internal backup landing zone | `jankaifer` + `nas-shared` write |
| `private` | Personal/admin-only files | `jankaifer` only |

## Service Contract

- Future Jellyfin reads from `/nas/media`
- Future *arr stack writes into `/nas/downloads` and imports into `/nas/media`
- Future NVR stack writes into `/nas/nvr`
- `/nas/downloads` is intentionally disposable and should stay outside backup scope
- `/nas/private` is included in restic backups
- Media libraries and NVR recordings are not currently added to offsite backup

## SMB and NFS Scope

Trusted networks:

- `192.168.2.0/24`
- `100.64.0.0/10`

Samba is exposed with host allow rules for LAN and Tailscale-style addresses.

NFS exports are published to both trusted network ranges with fixed ports for firewall stability.

## SMB Password Secrets

Required secrets:

- `nas-jankaifer-password.age`
- `nas-guest-password.age`

These are applied into Samba's local passdb by the `homelab-samba-users.service` activation helper.

## Validation

Check local directories:
```bash
find /nas -maxdepth 2 -type d | sort
```

Inspect Samba configuration:
```bash
testparm -s
```

Inspect NFS exports:
```bash
sudo exportfs -v
```

Check share services:
```bash
systemctl status samba-smbd samba-nmbd nfs-server
```
