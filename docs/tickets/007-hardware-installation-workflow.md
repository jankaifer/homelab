# Ticket 007: Hardware Installation Workflow

**Status**: DONE
**Created**: 2026-01-31
**Updated**: 2026-02-02

## Task

Research and create a script/workflow that makes installing NixOS on new hardware simple and fast. The goal is to go from bare metal to a fully configured homelab server with minimal manual steps.

## Questions to Research

1. **Installation approach**:
   - NixOS installer ISO with post-install config pull?
   - nixos-anywhere (install over SSH from existing Linux/live USB)?
   - Custom ISO with config baked in?
   - disko for declarative disk partitioning?

2. **Hardware detection**:
   - How to generate hardware.nix for new machines?
   - Handle different disk layouts (NVMe vs SATA, single vs RAID)?

3. **Secrets bootstrapping**:
   - How to get agenix secrets working on first boot?
   - SSH host key generation and adding to secrets.nix?

4. **Network configuration**:
   - Static IP vs DHCP for initial setup?
   - How to handle different network interfaces?

## Research Findings

### Recommended Approach: nixos-anywhere + disko

**nixos-anywhere** is the community-standard tool for remote NixOS installation:
- Installs NixOS over SSH from any Linux live environment
- Uses kexec to boot into a temporary RAM-based NixOS installer
- Integrates with disko for declarative disk partitioning
- Single command installs everything unattended
- Works for cloud servers, bare metal, and local LAN machines

**disko** provides declarative disk partitioning:
- Define disk layout in Nix (GPT, LVM, LUKS, ZFS, ext4, btrfs, etc.)
- Reproducible - same config always creates same layout
- Integrates seamlessly with nixos-anywhere

### Hardware Detection

nixos-anywhere can auto-generate hardware-configuration.nix:
```bash
nix run github:nix-community/nixos-anywhere -- \
  --generate-hardware-config nixos-generate-config ./hardware-configuration.nix \
  --flake .#server --target-host root@<ip>
```

### Secrets Bootstrapping (agenix)

Options for getting SSH host keys on new machines:

1. **Pre-generate keys** (recommended for homelab):
   - Generate SSH host key pair before installation
   - Add public key to `secrets.nix`
   - Re-encrypt secrets with new key
   - Use `--extra-files` to copy private key during install

2. **Two-phase install**:
   - Install without secrets first
   - SSH in, get the auto-generated host key
   - Add to secrets.nix, re-encrypt, rebuild

3. **Copy existing keys** (`--copy-host-keys`):
   - Only works if target already has keys you want to preserve

### Workflow Summary

1. Boot target from NixOS minimal ISO (USB stick)
2. Ensure SSH is accessible (it is by default on installer)
3. Run nixos-anywhere from local machine with the flake
4. Target reboots into fully configured system

## Implementation Plan

### Option A: Simple Script (Recommended)
Create `scripts/install-server.sh` that:
1. Takes target IP as argument
2. Runs nixos-anywhere with appropriate flags
3. Optionally generates hardware config for new machines
4. Handles disko disk configuration

**Pros**: Simple, works with existing flake structure
**Cons**: Need to manually boot installer ISO first

### Option B: Custom ISO
Build custom NixOS ISO with:
- SSH pre-enabled with your public keys
- Automated install script on boot
- Pre-configured for your hardware

**Pros**: More automated, "plug and play"
**Cons**: More complex to maintain, need to rebuild ISO for changes

### Proposed File Structure

```
homelab/
├── disko/
│   └── default.nix         # Disk layout configuration
├── scripts/
│   └── install-server.sh   # Installation wrapper script
└── machines/
    └── server/
        ├── default.nix
        └── hardware.nix    # Can be auto-generated
```

### Steps to Implement

1. Add disko as flake input
2. Create disko configuration for server disk layout
3. Integrate disko module into server config
4. Create install script wrapping nixos-anywhere
5. Document the installation process
6. Test in VM first

## Work Log

### 2026-01-31

- Ticket created
- Researched nixos-anywhere, disko, and agenix bootstrapping
- Key sources:
  - https://github.com/nix-community/nixos-anywhere
  - https://github.com/nix-community/disko
  - https://nix-community.github.io/nixos-anywhere/howtos/secrets.html
  - https://michael.stapelberg.ch/posts/2025-06-01-nixos-installation-declarative/
- Recommendation: Use nixos-anywhere + disko (Option A)

**Implementation completed:**
- Added disko as flake input
- Created `machines/server/disko.nix` with GPT + EFI + ext4 layout
- Updated `secrets/secrets.nix` with placeholder for server key (replaced during install)
- Created `scripts/install-server.sh` that:
  - Generates SSH host key on-the-fly
  - Updates secrets.nix with public key
  - Re-encrypts secrets automatically
  - Runs nixos-anywhere with the private key
- Created `docs/services/installation.md` documentation
- Updated `docs/OVERVIEW.md` with installation instructions

**Workflow:**
1. Boot target from NixOS minimal ISO
2. Run `./scripts/install-server.sh <ip>`
3. Commit updated secrets.nix after install

### 2026-02-01: First Real Hardware Installation

**Hardware:** Framework laptop mainboard (no antennas - weak WiFi)

**Issues encountered:**
- WiFi very unstable on 5GHz without proper antennas
- Docker x86 emulation on Apple Silicon very slow for nix downloads
- nixos-anywhere downloads from cache.nixos.org kept hanging

**Solutions applied:**
1. Switched server WiFi from 5GHz to 2.4GHz (better range)
2. Enabled USB tethering via Android phone for stable internet
3. Ran `nixos-install` directly on server instead of through Docker

**What worked:**
- SSH host key was pre-generated and added to secrets.nix
- disko formatted disk correctly (1.8TB NVMe: 512MB EFI + ext4)
- Installation completed with 5130 packages
- Bootloader (systemd-boot) installed successfully

**Current state:**
- Server booted into NixOS but no network (WiFi not configured in NixOS)
- Need to configure WiFi manually: `nmcli device wifi connect "Hobitín" password "tecenamdosklepa"`
- Login: root/nixos or admin/nixos

**TODO:**
- Add WiFi credentials to NixOS config (use agenix wifi-password.age)
- Update secrets.nix to include server key for wifi-password.age
- Re-encrypt wifi-password.age with server key

### 2026-02-01: Bug Fix - SSH Keys Missing

**Issue:** After installation, couldn't SSH in with keys - server config had no `openssh.authorizedKeys` configured.

**Fix:** Updated `machines/server/default.nix` to:
- Import SSH keys from `lib/ssh-keys.nix`
- Add all user keys to root and admin users' `openssh.authorizedKeys.keys`

This ensures all keys defined in `lib/ssh-keys.nix` are automatically authorized on the server.

### 2026-02-02: Server Successfully Booting from NVMe

**Context:** Added proper WiFi antenna to Framework mainboard, booted from installer ISO to fix remaining issues.

**Issues encountered:**
1. Newer installer ISO had SSH key authentication failing (keys not matching)
2. Installed system (from Jan 26 build) missing SSH authorized_keys and WiFi config
3. System kept booting from installer USB instead of NVMe
4. SSH connections getting "connection reset" when booting from installer with I/O errors

**Fixes applied:**
1. Used older working installer ISO that had correct SSH keys
2. Mounted installed system from installer and manually added:
   - SSH authorized keys to `/etc/ssh/authorized_keys.d/root` and `/etc/ssh/authorized_keys.d/admin`
   - NetworkManager WiFi connection profile at `/etc/NetworkManager/system-connections/Hobitín.nmconnection`
3. Unplugged installer USB and force-rebooted to boot from NVMe

**Final state - Server running from NVMe:**
- Hostname: `server`
- IP: `192.168.2.241` (USB WiFi adapter, DHCP)
- NixOS version: 26.05.20260126.bfc1b8a
- Disk: 1.8TB NVMe, 5.3GB used
- Services:
  - SSH: active
  - NetworkManager: active
  - Grafana: active
  - Caddy: failed (needs agenix secrets - requires rebuild from current flake)

**Next steps:**
1. Run `nixos-rebuild switch --flake .#server` to apply current config with:
   - Proper SSH keys baked into NixOS config
   - WiFi credentials via agenix (if configured)
   - Working Caddy with secrets
2. Consider adding WiFi credentials to NixOS config declaratively
