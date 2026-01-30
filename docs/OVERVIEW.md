# Homelab Overview

This document describes the current state of the homelab infrastructure.

## Architecture

NixOS-based homelab using flakes for reproducible, declarative configuration.

```
┌─────────────────────────────────────────────────────────┐
│                      NixOS Server                        │
│  ┌─────────────────┐  ┌─────────────────┐               │
│  │    Homepage     │  │      SSH        │               │
│  │   (port 3000)   │  │   (port 22)     │               │
│  └─────────────────┘  └─────────────────┘               │
│                                                          │
│  ┌─────────────────┐                                    │
│  │     Caddy       │  (defined, not enabled)            │
│  │  (reverse proxy)│                                    │
│  └─────────────────┘                                    │
└─────────────────────────────────────────────────────────┘
```

## Machine Configurations

| Machine | Architecture | Purpose |
|---------|--------------|---------|
| `server` | x86_64-linux | Production deployment |
| `server-vm` | aarch64-linux | Local testing on Apple Silicon |

## Enabled Services

| Service | Port | Status | Documentation |
|---------|------|--------|---------------|
| Homepage | 3000 | Enabled | [docs/services/homepage.md](services/homepage.md) |
| SSH | 22 | Enabled | [docs/services/ssh.md](services/ssh.md) |
| Caddy | 80/443 | Defined, not enabled | [docs/services/caddy.md](services/caddy.md) |

## Users

| Username | Type | Password (VM only) | Notes |
|----------|------|-------------------|-------|
| `root` | System | `nixos` | For VM testing only |
| `admin` | Normal | `nixos` | Has sudo (no password), wheel group |

**Warning:** These passwords are for VM testing only. Production should use agenix-encrypted secrets.

## Development Workflow

```bash
# Validate config (fast, no Docker needed)
nix eval .#nixosConfigurations.server-vm.config.system.build.toplevel --apply 'x: x.drvPath'

# Build and run VM
./scripts/run-vm-docker.sh

# Access services
# Homepage: http://localhost:3000
# SSH: ssh -p 2222 root@localhost
```

## Directory Structure

```
homelab/
├── flake.nix              # Main entry point, defines machines
├── machines/
│   └── server/
│       ├── default.nix    # Server config (services, users, etc.)
│       └── hardware.nix   # Hardware-specific settings
├── modules/
│   └── services/          # Reusable service modules
│       ├── homepage.nix
│       └── caddy.nix
├── secrets/               # agenix encrypted secrets
├── scripts/               # Development scripts
│   ├── run-vm-docker.sh   # Build and run VM
│   └── nix-build-docker.sh
└── docs/
    ├── OVERVIEW.md        # This file
    ├── PROJECT_PLAN.md    # Future plans
    ├── services/          # Per-service documentation
    └── tickets/           # Task tracking
```

## Next Steps

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the roadmap and [tickets/](tickets/) for active tasks.
