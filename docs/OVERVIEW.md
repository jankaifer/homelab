# Homelab Overview

This document describes the current state of the homelab infrastructure.

## Architecture

NixOS-based homelab using flakes for reproducible, declarative configuration.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              NixOS Server                                   │
│                                                                             │
│  ┌──────────────────┐                                                       │
│  │      Caddy       │  (reverse proxy, ports 80/443)                        │
│  │  *.lan.kaifer.dev│  (TLS via Cloudflare DNS challenge)                   │
│  └────────┬─────────┘                                                       │
│           │                                                                 │
│  ┌────────▼────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │    Homepage     │  │ VictoriaMetrics │  │      Loki       │              │
│  │lan.kaifer.dev   │  │metrics.lan...   │  │ logs.lan...     │              │
│  │ (internal:3000) │  │ (internal:8428) │  │ (internal:3100) │              │
│  └─────────────────┘  └────────┬────────┘  └────────▲────────┘              │
│                                │ scrapes            │ pushes                │
│                       ┌────────▼────────┐  ┌───────┴────────┐               │
│                       │  node_exporter  │  │    Promtail    │               │
│                       │   (port 9100)   │  │ (journal logs) │               │
│                       └─────────────────┘  └────────────────┘               │
│                                                                             │
│  ┌─────────────────┐                                                        │
│  │      SSH        │  (port 22)                                             │
│  └─────────────────┘                                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Machine Configurations

| Machine | Architecture | Purpose |
|---------|--------------|---------|
| `server` | x86_64-linux | Production deployment |
| `server-vm` | aarch64-linux | Local testing on Apple Silicon |

## Enabled Services

| Service | Port | URL | Documentation |
|---------|------|-----|---------------|
| Caddy | 80/443 | (reverse proxy) | [docs/services/caddy.md](services/caddy.md) |
| Homepage | 3000 (internal) | https://lan.kaifer.dev | [docs/services/homepage.md](services/homepage.md) |
| VictoriaMetrics | 8428 (internal) | https://metrics.lan.kaifer.dev | [docs/services/victoriametrics.md](services/victoriametrics.md) |
| Loki | 3100 (internal) | https://logs.lan.kaifer.dev | [docs/services/loki.md](services/loki.md) |
| SSH | 22 | `ssh -p 2222 root@localhost` (VM) | [docs/services/ssh.md](services/ssh.md) |

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

# Access services (VM testing with port 8443)
# Homepage: https://lan.kaifer.dev:8443
# VictoriaMetrics: https://metrics.lan.kaifer.dev:8443
# Loki: https://logs.lan.kaifer.dev:8443
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
│       ├── caddy.nix
│       ├── homepage.nix
│       ├── loki.nix
│       └── victoriametrics.nix
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
