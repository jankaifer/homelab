# AGENTS.md

This file defines the default guidance for Codex and other coding agents in this repository.

## Project Overview

NixOS homelab configuration using flakes. The structure separates machine configs from reusable service modules.

- `docs/OVERVIEW.md` - Current state of the infrastructure
- `docs/PROJECT_PLAN.md` - Plans and roadmap
- `docs/services/` - Per-service documentation
- `docs/tickets/` - Ticket-based work log

## Core Commands

```bash
# Quick validation - check config evaluates correctly (fast, works on macOS)
nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'

# Build and run VM using Docker (recommended for macOS)
./scripts/run-vm-docker.sh

# Build only (can run in background)
./scripts/run-vm-docker.sh --build

# Format nix files
nix fmt
```

## Machine Configurations

- `frame1` - Production config (x86_64-linux)
- `frame1-vm` - VM testing config (aarch64-linux, Apple Silicon friendly)
- `installer-iso` - Bootable installer ISO config

## Directory Structure

- `machines/` - Per-machine NixOS configurations
- `modules/services/` - Reusable service modules (caddy, homepage, grafana, etc.)
- `secrets/` - agenix encrypted secrets
- `scripts/` - Build/install/test workflows
- `docs/` - Project documentation

## Module Convention

Services use `homelab.services.<name>.enable`. Machines import modules and enable only what they need.

## Documentation Rules

Keep docs current when behavior changes.

### When adding a new service

1. Create module: `modules/services/<name>.nix`
2. Create docs: `docs/services/<name>.md` including:
   - Status (enabled/disabled)
   - Configuration options
   - Access URLs/ports
   - Dependencies
   - Upstream references
3. Update `docs/OVERVIEW.md`

### When modifying a service

1. Update the relevant `docs/services/<name>.md`
2. Update `docs/OVERVIEW.md` if status/endpoints changed

## macOS Build/Test Workflow

NixOS builds need Linux. On Apple Silicon/macOS, use Docker.

### Prerequisites

- Docker Desktop installed and running

### Build and run

```bash
# Build and run VM interactively
./scripts/run-vm-docker.sh

# Build only
./scripts/run-vm-docker.sh --build
```

Port forwarding:
- Caddy HTTP: `http://localhost:8080` -> VM `:80`
- Caddy HTTPS: `https://local.kaifer.dev:8443` -> VM `:443`
- SSH: `ssh -p 2222 root@localhost`

Subdomain DNS setup for local testing:

```bash
sudo tee -a /etc/hosts <<EOF
# Homelab VM testing
127.0.0.1 local.kaifer.dev
127.0.0.1 grafana.local.kaifer.dev
127.0.0.1 metrics.local.kaifer.dev
127.0.0.1 logs.local.kaifer.dev
EOF
```

See `docs/vm-testing-dns.md` for details.

## Assistant Workflow (Codex)

1. Make the config change
2. Run `nix eval` for fast validation
3. Run `./scripts/run-vm-docker.sh --build` for build verification
4. Boot VM with `./scripts/run-vm-docker.sh` when runtime behavior must be verified
5. Update docs/tickets for notable changes

## Deployment Workflow

Use deploy-rs for safe production deployment.

### Deployment Policy (Mandatory)

1. Deploy **only** with `deploy-rs` (via `nix run .#deploy -- ...`).
2. Always keep **both** rollback protections enabled:
   - `magicRollback = true`
   - `autoRollback = true`
3. Do not deploy production with `nixos-rebuild switch` directly.

Use these commands:

```bash
# Deploy to frame1
nix run .#deploy -- .#frame1 --skip-checks

# Dry run (test activation only)
nix run .#deploy -- .#frame1 --dry-activate --skip-checks
```

Deployment behavior:
1. Build closure (local/remote builder as configured)
2. Copy closure to target
3. Activate with timeout
4. Auto-rollback if activation/SSH fails

## Ticket Workflow

Track work in `docs/tickets/NNN-short-name.md`.

Ticket format:

```markdown
# Ticket NNN: Title

**Status**: PLANNING | IN_PROGRESS | BLOCKED | DONE
**Created**: YYYY-MM-DD
**Updated**: YYYY-MM-DD

## Task
[Description]

## Implementation Plan
[Agreed approach]

## Work Log
### YYYY-MM-DD
[Discoveries, decisions, progress]
```
