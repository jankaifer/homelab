# Installer ISO

Minimal bootable NixOS ISO for headless server installation.

## Status

**Enabled** - Build with `./scripts/build-installer-iso.sh`

## Features

- Auto-connects to home WiFi (`Hobitín`)
- SSH server running on boot with root login enabled
- Your SSH keys pre-authorized (from `lib/ssh-keys.nix`)
- Includes git and vim for convenience

## Building

```bash
# Requires Docker and your SSH key (~/.ssh/id_ed25519)
./scripts/build-installer-iso.sh
```

The script:
1. Decrypts WiFi password from `secrets/wifi-password.age` using your SSH key
2. Builds the ISO in Docker (x86_64-linux)
3. Outputs to `result/iso/nixos-*.iso`

## Flashing to USB

```bash
# Find your USB device (usually /dev/sdX on Linux, /dev/diskN on macOS)
lsblk  # or: diskutil list

# Flash (replace /dev/sdX with your device)
sudo dd if=result/iso/nixos-*.iso of=/dev/sdX bs=4M status=progress
```

On macOS:
```bash
# Unmount first
diskutil unmountDisk /dev/diskN

# Flash (use rdiskN for faster writes)
sudo dd if=result/iso/nixos-*.iso of=/dev/rdiskN bs=4m
```

## Usage

1. Boot server from USB
2. Wait for WiFi to connect (automatic)
3. Find the server's IP (check router DHCP leases, or `nmap -sn 192.168.1.0/24`)
4. SSH in: `ssh root@<ip>`
5. Run nixos-anywhere from your workstation to install

## Access

| Service | Endpoint |
|---------|----------|
| SSH on booted installer | `ssh root@<installer-ip>` |

## Configuration

- `machines/installer-iso/default.nix` - ISO configuration
- `lib/ssh-keys.nix` - SSH public keys (shared with agenix)
- `secrets/wifi-password.age` - Encrypted WiFi password

## Dependencies

- Docker (for building on macOS)
- age CLI (for decrypting WiFi password)
- Your SSH key matching one in `lib/ssh-keys.nix`

## Links

- [NixOS Downloads](https://nixos.org/download/)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [disko](https://github.com/nix-community/disko)
