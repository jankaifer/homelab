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

# Build VM for testing (requires linux-builder running - see below)
nix build .#nixosConfigurations.server-vm.config.system.build.vm

# Run VM
./result/bin/run-server-vm

# Run VM with port forwarding (access Homepage on localhost:3000, SSH on 2222)
QEMU_NET_OPTS="hostfwd=tcp::3000-:3000,hostfwd=tcp::2222-:22" ./result/bin/run-server-vm

# Format nix files
nix fmt
```

## Machine Configurations

- `server` - Production config (x86_64-linux)
- `server-vm` - VM testing config (aarch64-linux, for Apple Silicon Macs)

## Directory Structure

- `machines/` - Per-machine NixOS configurations
- `modules/services/` - Reusable service modules (caddy, homepage, etc.)
- `secrets/` - agenix encrypted secrets
- `docs/` - Project documentation

## Module Convention

Services use `homelab.services.<name>.enable` pattern. Machines import modules and enable what they need.

## Building on macOS (Apple Silicon)

Building NixOS requires a Linux builder. Use the free nixpkgs linux-builder:

### One-time setup

```bash
# 1. Start the linux-builder (will prompt for sudo to install SSH keys)
nix run nixpkgs#darwin.linux-builder

# 2. In another terminal, add builder to nix config
sudo tee -a /etc/nix/nix.custom.conf << 'EOF'
builders = ssh-ng://linux-builder aarch64-linux /etc/nix/builder_ed25519 4 - - - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU9BMWZHWVRYZ1B0SG9OMkVVSTlVTjAyRUhIVU5Fd2oyWXV3aG5NOUVVTmkgcm9vdEBuaXhvcwo=
builders-use-substitutes = true
EOF

# 3. Restart nix daemon
sudo launchctl kickstart -k system/systems.determinate.nix-daemon
```

### Each session

```bash
# Terminal 1: Keep linux-builder running
nix run nixpkgs#darwin.linux-builder

# Terminal 2: Build and test
nix build .#nixosConfigurations.server-vm.config.system.build.vm
```

## AI Workflow

1. Make config change
2. Run `nix eval` to validate syntax (fast, no builder needed)
3. Run `nix build` with linux-builder running to build VM
4. Boot VM and verify services work
5. Iterate

## Ticket Workflow

All work is tracked via ticket files in `docs/tickets/`. This provides context persistence across sessions.

### Ticket Lifecycle

1. **User assigns a ticket** - User describes the task
2. **Create ticket file** - Create `docs/tickets/NNN-short-name.md` with:
   - Task description
   - Initial questions/unknowns
3. **Plan iteration** - Discuss implementation approach with user until agreed
4. **Implementation** - Follow the plan, updating the ticket as a diary:
   - Noteworthy discoveries
   - Decisions made and rationale
   - Blockers encountered
   - Progress checkpoints
5. **Completion** - Mark status as DONE, summarize what was accomplished

### Ticket File Format

```markdown
# Ticket NNN: Title

**Status**: PLANNING | IN_PROGRESS | BLOCKED | DONE
**Created**: YYYY-MM-DD
**Updated**: YYYY-MM-DD

## Task

[Description of what needs to be done]

## Implementation Plan

[Agreed approach - filled in after planning discussion]

## Work Log

### YYYY-MM-DD

[Diary entries: discoveries, decisions, progress]
```

### Why This Matters

- **Context survives restarts** - New sessions can read tickets to continue work
- **Decisions are documented** - No re-debating already-decided issues
- **Progress is visible** - Easy to see what's done and what remains
