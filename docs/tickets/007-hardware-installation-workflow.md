# Ticket 007: Hardware Installation Workflow

**Status**: DONE
**Created**: 2026-01-31
**Updated**: 2026-01-31

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
