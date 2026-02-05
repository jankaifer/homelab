# Server Installation Guide

This guide covers how to install NixOS on new server hardware using the automated installation workflow.

## Overview

The installation uses:
- **nixos-anywhere**: Remote NixOS installation over SSH
- **disko**: Declarative disk partitioning
- **agenix**: SSH host key generated during install for secrets

## Prerequisites

1. **NixOS Minimal ISO** - Download from https://nixos.org/download
2. **USB stick** - To boot the installer on target hardware
3. **Network access** - Target must be reachable via SSH
4. **Nix installed** - On your local machine (with flakes enabled)

## Installation Steps

### 1. Prepare the USB Installer

Download the NixOS minimal ISO and write it to a USB stick:

```bash
# macOS
sudo dd if=nixos-minimal-*.iso of=/dev/diskN bs=4M status=progress

# Linux
sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
```

### 2. Boot Target Machine

1. Insert USB stick into target server
2. Boot from USB (may need to adjust BIOS/UEFI boot order)
3. Wait for NixOS installer to boot

### 3. Get Target IP Address

On the target machine (NixOS installer), find the IP:

```bash
ip addr
```

Or set a static IP if needed:

```bash
sudo ip addr add 192.168.1.100/24 dev eth0
sudo ip route add default via 192.168.1.1
```

### 4. Enable SSH Access

SSH is enabled by default on the installer. Set a password for root:

```bash
sudo passwd root
```

### 5. Run Installation Script

From your local machine:

```bash
./scripts/install-server.sh <target-ip>

# Example
./scripts/install-server.sh 192.168.1.100
```

The script automatically:
1. Generates a new SSH host key for the server
2. Updates `secrets.nix` with the public key
3. Re-encrypts all secrets so the server can decrypt them
4. Runs nixos-anywhere to partition and install
5. Copies the SSH host key to the server
6. Reboots into the configured system

### 6. Commit the Updated Secrets

After installation, commit the changes to secrets:

```bash
git add secrets/
git commit -m 'Update server SSH key after installation'
```

### 7. Verify Installation

SSH into the new server:

```bash
ssh root@<target-ip>
```

Check that services are running:

```bash
systemctl status caddy
systemctl status grafana
systemctl status victoriametrics
```

## Customization

### Different Disk Device

If your server uses SATA instead of NVMe, edit `machines/frame1/disko.nix`:

```nix
disko.devices.disk.main.device = "/dev/sda";  # or /dev/vda for VMs
```

### Static IP Configuration

For production, you'll want static IP. Add to `machines/frame1/default.nix`:

```nix
networking = {
  useDHCP = false;
  interfaces.enp0s3.ipv4.addresses = [{
    address = "192.168.1.10";
    prefixLength = 24;
  }];
  defaultGateway = "192.168.1.1";
  nameservers = [ "1.1.1.1" "8.8.8.8" ];
};
```

## How Secrets Work

The install script handles the "chicken and egg" problem of agenix secrets:

1. **Key generation**: A fresh SSH host key is generated in a temp directory
2. **secrets.nix update**: The public key replaces the placeholder in `secrets.nix`
3. **Re-encryption**: `agenix -r` re-encrypts all secrets with the new key
4. **Installation**: nixos-anywhere copies the private key to `/etc/ssh/`
5. **Boot**: The server can now decrypt secrets using its host key

The private key only exists:
- Temporarily on your machine during install (deleted after)
- Permanently on the server at `/etc/ssh/ssh_host_ed25519_key`

The public key is committed to git in `secrets.nix` (safe to share).

## Reinstallation

To reinstall the server (e.g., after hardware changes):

1. Run `./scripts/install-server.sh <ip>` again
2. A new SSH key will be generated
3. Secrets will be re-encrypted
4. Commit the updated `secrets.nix`

## Troubleshooting

### SSH Connection Refused

Ensure the installer has booted and SSH is accessible:
```bash
# On target machine
systemctl status sshd
```

### Disk Not Found

Check available disks on the target:
```bash
lsblk
```

Update `machines/frame1/disko.nix` with the correct device path.

### Secrets Not Decrypting

Verify the SSH host key was copied correctly:
```bash
ls -la /etc/ssh/ssh_host_ed25519_key*
```

Check agenix status:
```bash
journalctl -u agenix
```

### agenix -r Fails

Ensure you have one of the user keys (jankaifer-1, jankaifer-2, or jk-cf) available:
```bash
ssh-add -l  # Should show one of the keys from secrets.nix
```

## Related Documentation

- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [disko](https://github.com/nix-community/disko)
- [agenix](https://github.com/ryantm/agenix)
- [Secrets Management](../secrets.md)
