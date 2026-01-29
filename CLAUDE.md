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

# Build and run VM using Docker (recommended for macOS)
./scripts/run-vm-docker.sh

# Build only (can run in background)
./scripts/run-vm-docker.sh --build

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

Building NixOS requires a Linux environment. We use Docker for simplicity.

### Prerequisites

- Docker Desktop installed and running

### Building and Running

```bash
# Build and run VM interactively
# This builds inside Docker and runs QEMU with port forwarding
./scripts/run-vm-docker.sh

# Build only (can run in background)
./scripts/run-vm-docker.sh --build
```

**Port forwarding:**
- Homepage: http://localhost:3000
- SSH: ssh -p 2222 root@localhost

**How it works:**
- Uses `nixos/nix:latest` Docker image
- Persistent `homelab-nix-store` volume caches packages for fast rebuilds
- First build takes ~25 min (kernel modules compilation)
- Subsequent builds are much faster

**Exit QEMU:** Press `Ctrl+A, X`

## AI Workflow

1. Make config change
2. Run `nix eval` to validate syntax (fast, no Docker needed)
3. Run `./scripts/run-vm-docker.sh --build` to build VM (can run in background)
4. Run `./scripts/run-vm-docker.sh` to boot VM and verify services work
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
