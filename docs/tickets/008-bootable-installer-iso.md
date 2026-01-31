# Ticket 008: Bootable Installer ISO

**Status**: DONE
**Created**: 2026-01-31
**Updated**: 2026-01-31

## Task

Create a bootable NixOS ISO for server installation that:
1. Auto-connects to home WiFi (pre-configured credentials)
2. SSH server running on boot
3. User's SSH keys pre-authorized for root login
4. Minimal - just enough for remote installation via nixos-anywhere

## Purpose

Flash to USB stick, boot servers, SSH in remotely to run `nixos-anywhere` installation without needing keyboard/monitor attached.

## Decisions

- **WiFi SSID**: `Hobitín`
- **WiFi password**: Stored in agenix, decrypted at build time by builder machine
- **Architecture**: x86_64-linux only
- **Extra tools**: git and vim included

## Implementation Plan

### 1. Create agenix secret for WiFi

Create `secrets/wifi-password.age` containing just the password (SSID is hardcoded in config).

Encrypted to user keys only (not server - server doesn't need this).

### 2. Create ISO configuration

Create `machines/installer-iso/default.nix`:

```nix
{ config, pkgs, lib, ... }:
{
  # Base on minimal installer
  imports = [
    "${toString pkgs.path}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # WiFi - password injected at build time via --argstr
  networking.wireless = {
    enable = true;
    networks."Hobitín" = {
      psk = builtins.getEnv "WIFI_PASSWORD";
    };
  };

  # SSH server enabled by default in installer, but ensure root login
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Authorized SSH keys for root
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJe9IWxd3nIG9qm86UMTZeVHHeHN5eh6nHu7KwU+x/fz"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQZcA7EKUH91Sp4s2aRNJ6sOgZCUx9CqDuaEiPvWjWC"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG6x4L/uYrM/KmYBTvvl3FaO2T3T5Vf+uAnEKA43BwU"
  ];

  # Extra tools
  environment.systemPackages = with pkgs; [
    git
    vim
  ];
}
```

### 3. Add to flake.nix

```nix
nixosConfigurations.installer-iso = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [ ./machines/installer-iso ];
};
```

### 4. Create build script

Create `scripts/build-installer-iso.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Decrypt WiFi password from agenix
export WIFI_PASSWORD=$(cd secrets && age -d -i ~/.ssh/id_ed25519 wifi-password.age)

# Build ISO (requires x86_64-linux builder)
nix build .#nixosConfigurations.installer-iso.config.system.build.isoImage \
  --impure  # needed for getEnv

echo "ISO built at: ./result/iso/*.iso"
```

### 5. Building on macOS

Since this needs x86_64-linux, options:
1. **Docker with binfmt** - Similar to current VM build approach
2. **Remote builder** - If you have an x86_64-linux machine
3. **GitHub Actions** - Build in CI, download artifact

### 6. Documentation

Create `docs/services/installer-iso.md` with usage instructions.

## Files Created/Modified

- [x] `lib/ssh-keys.nix` - Shared SSH keys (new)
- [x] `secrets/wifi-password.age` - Encrypted WiFi password
- [x] `secrets/secrets.nix` - Updated to import from lib/ssh-keys.nix
- [x] `machines/installer-iso/default.nix` - ISO configuration
- [x] `flake.nix` - Added installer-iso output
- [x] `scripts/build-installer-iso.sh` - Build script (Docker-based)
- [x] `docs/services/installer-iso.md` - Documentation
- [x] `docs/OVERVIEW.md` - Updated with installer-iso info

## Technical Notes

### SSH Keys (from secrets.nix)

Already have these defined:
- `jankaifer-1`: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJe9IWxd3nIG9qm86UMTZeVHHeHN5eh6nHu7KwU+x/fz
- `jankaifer-2`: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQZcA7EKUH91Sp4s2aRNJ6sOgZCUx9CqDuaEiPvWjWC
- `jk-cf`: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG6x4L/uYrM/KmYBTvvl3FaO2T3T5Vf+uAnEKA43BwU

### NixOS ISO Building

NixOS provides ISO building via:
```nix
# In flake.nix outputs
nixosConfigurations.installer-iso = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    ./machines/installer-iso/default.nix
  ];
};

# Build command
nix build .#nixosConfigurations.installer-iso.config.system.build.isoImage
```

### WiFi Configuration (wpa_supplicant)

```nix
networking.wireless = {
  enable = true;
  networks."SSID_HERE" = {
    psk = "password_here";  # or pskRaw for pre-hashed
  };
};
```

## Work Log

### 2026-01-31

- Ticket created
- Identified SSH keys already in secrets.nix
- User decisions:
  - WiFi SSID: `Hobitín`
  - WiFi password in agenix, decrypted at build time
  - x86_64-linux only
  - Include git + vim
- Implementation plan drafted

**Implementation completed:**
- Created `lib/ssh-keys.nix` to share SSH keys between agenix and ISO
- Updated `secrets/secrets.nix` to import keys from shared file
- Created `secrets/wifi-password.age` with encrypted WiFi password
- Created `machines/installer-iso/default.nix`:
  - Uses `modulesPath` for installer CD import (avoids infinite recursion)
  - Disables NetworkManager (conflicts with wpa_supplicant)
  - WiFi password from `WIFI_PASSWORD` env var with conditional (allows eval without env)
  - SSH keys from shared `lib/ssh-keys.nix`
  - Includes git and vim
  - Helpful MOTD with instructions
- Created `scripts/build-installer-iso.sh` - reuses Docker pattern from run-vm-docker.sh
- Updated `flake.nix` with installer-iso configuration
- Created documentation at `docs/services/installer-iso.md`
- Updated `docs/OVERVIEW.md` with new machine and directory structure

**Build command:**
```bash
./scripts/build-installer-iso.sh
# Output: result/iso/nixos-*.iso
```
