# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Allowed Tools

- Bash(*)

## Project Overview

NixOS homelab configuration using flakes. Modular structure separating machine configs from service modules.

See `docs/PROJECT_PLAN.md` for full architecture details.

## Commands

```bash
# Validate config builds (fast, no VM)
nix build .#nixosConfigurations.server.config.system.build.toplevel --dry-run

# Build VM for testing
nix build .#nixosConfigurations.server.config.system.build.vm

# Run VM (requires QEMU)
./result/bin/run-server-vm

# Run VM with port forwarding (access services from host)
QEMU_NET_OPTS="hostfwd=tcp::8080-:80" ./result/bin/run-server-vm

# Format nix files
nix fmt
```

## Directory Structure

- `machines/` - Per-machine NixOS configurations
- `modules/services/` - Reusable service modules (caddy, prometheus, etc.)
- `secrets/` - agenix encrypted secrets
- `docs/` - Project documentation

## Module Convention

Services use `homelab.services.<name>.enable` pattern. Machines import modules and enable what they need.

## AI Workflow

1. Make config change
2. Run `nix build .#nixosConfigurations.server.config.system.build.vm`
3. Boot VM and verify
4. Iterate

For quick syntax/build validation without VM: use `--dry-run` flag.
