# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Allowed Tools

- Bash(*)

## Project Overview

NixOS homelab configuration using flakes. Modular structure separating machine configs from service modules.

See `docs/PROJECT_PLAN.md` for full architecture details.

## Commands

```bash
# Quick validation - check config evaluates correctly (fast, works on macOS)
nix eval .#nixosConfigurations.server-vm.config.system.build.toplevel --apply 'x: x.drvPath'

# Build VM for testing (requires Linux builder - see notes below)
nix build .#nixosConfigurations.server-vm.config.system.build.vm

# Run VM (requires QEMU)
./result/bin/run-server-vm

# Run VM with port forwarding (access services from host)
QEMU_NET_OPTS="hostfwd=tcp::3000-:3000,hostfwd=tcp::2222-:22" ./result/bin/run-server-vm

# Format nix files
nix fmt
```

## Machine Configurations

- `server` - Production config (x86_64-linux)
- `server-vm` - VM testing config (aarch64-linux, for Apple Silicon Macs)

## Directory Structure

- `machines/` - Per-machine NixOS configurations
- `modules/services/` - Reusable service modules (caddy, prometheus, etc.)
- `secrets/` - agenix encrypted secrets
- `docs/` - Project documentation

## Module Convention

Services use `homelab.services.<name>.enable` pattern. Machines import modules and enable what they need.

## AI Workflow

1. Make config change
2. Run `nix eval` to validate (fast)
3. If Linux builder available: build and boot VM to verify
4. Iterate

## Building on macOS

Building NixOS (Linux) on macOS requires a Linux builder. Options:
- Determinate Nix Linux Builder (subscription required)
- Remote Linux machine as builder
- GitHub Actions for CI builds
- nixbuild.net

For local development, use `nix eval` for quick validation.
