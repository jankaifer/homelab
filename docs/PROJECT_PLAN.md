# Homelab Project Plan

## Overview

NixOS-based homelab configuration with flakes. Optimized for AI-assisted development with a fast feedback loop via VM testing.

## Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| OS | NixOS with Flakes | Declarative, reproducible, rollback support |
| Secrets | agenix | Integrates well with NixOS, age encryption |
| Reverse Proxy | Caddy | Simple config, automatic HTTPS |
| Monitoring | VictoriaMetrics + Loki + Grafana | Prometheus-compatible, more efficient |
| Log Collection | Alloy | Modern collector, ships journal to Loki |
| Installation | nixos-anywhere + disko | Remote install with declarative partitioning |
| Dashboard | Homepage | Simple, configurable service dashboard |

## Directory Structure

```
/
├── flake.nix                 # Main flake - defines inputs, outputs, machines
├── flake.lock
├── machines/
│   └── frame1/
│       ├── default.nix       # Machine config - imports needed modules
│       ├── disko.nix         # Declarative disk partitioning
│       ├── hardware.nix      # Hardware-specific settings
│       └── vm.nix            # VM-specific config (agenix via host SSH)
├── modules/
│   └── services/             # One module per service, toggleable
│       ├── alloy.nix
│       ├── caddy.nix
│       ├── grafana.nix
│       ├── homepage.nix
│       ├── loki.nix
│       └── victoriametrics.nix
├── secrets/
│   ├── secrets.nix           # agenix secret declarations
│   └── *.age                 # Encrypted secret files
├── scripts/
│   ├── install-server.sh     # Automated hardware installation
│   └── run-vm-docker.sh      # VM testing on macOS
├── docs/
│   ├── OVERVIEW.md           # Current state
│   ├── PROJECT_PLAN.md       # This file
│   └── services/             # Per-service documentation
└── CLAUDE.md
```

### Design Principles

1. **Machines import modules** - Each machine picks which services it runs
2. **Modules are self-contained** - Service module includes its NixOS config, not machine-specific details
3. **Secrets reference by path** - Modules expect secrets at known paths, agenix provides them

## Machine Configurations

| Name | System | Purpose |
|------|--------|---------|
| `frame1` | x86_64-linux | Production server deployment |
| `frame1-vm` | aarch64-linux | Local VM testing on Apple Silicon |

## AI Development Workflow

### Quick Validation (no Docker needed)

```bash
# Check config evaluates correctly - fast syntax/type checking
nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'
```

### Full VM Testing (Docker-based)

Building NixOS requires Linux. We use Docker for simplicity on macOS.

```bash
# Build only (can run in background)
./scripts/run-vm-docker.sh --build

# Build and run VM interactively
./scripts/run-vm-docker.sh
```

**How it works:**
- Uses `nixos/nix:latest` Docker image for building
- Persistent `homelab-nix-store` volume caches packages
- QEMU runs inside Docker with TCG emulation
- First build takes ~25 min, subsequent builds are fast

**Port forwarding:**
- HTTP: localhost:8080 → VM:80
- HTTPS: localhost:8443 → VM:443
- SSH: localhost:2222 → VM:22

**Access services:**
- Homepage (via Caddy): https://lan.kaifer.dev:8443
- SSH: `ssh -p 2222 root@localhost` (password: `nixos`)

**Exit QEMU:** Press `Ctrl+A, X`

## Initial Scope

### Phase 1: Foundation ✓
- [x] Basic flake.nix with NixOS configuration
- [x] Server machine definition
- [x] VM configuration for Apple Silicon testing
- [x] Working VM build (Docker-based workflow)

### Phase 2: Core Services ✓
- [x] Homepage module (dashboard)
- [x] Caddy module (reverse proxy with Let's Encrypt via Cloudflare DNS)

### Phase 3: Observability ✓
- [x] VictoriaMetrics module (Prometheus-compatible metrics)
- [x] Loki module (log aggregation)
- [x] Alloy module (log collection from systemd journal)
- [x] Grafana module (dashboards)
- [x] Caddy routes for all services

### Phase 4: Secrets ✓
- [x] agenix structure ready
- [x] SSH keys for secret encryption
- [x] Cloudflare API token (encrypted)
- [x] Grafana admin password (encrypted)

### Phase 5: Production Deployment ✓
- [x] disko for declarative disk partitioning
- [x] nixos-anywhere integration
- [x] Automated install script (scripts/install-server.sh)
- [x] SSH host key generation during install
- [x] Secrets re-encryption workflow

## Module Pattern

Each service module follows this pattern:

```nix
# modules/services/example.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.example;
in
{
  # Option to enable/disable this service
  options.homelab.services.example = {
    enable = lib.mkEnableOption "example service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for example service";
    };
  };

  # Actual configuration when enabled
  config = lib.mkIf cfg.enable {
    services.example = {
      enable = true;
      port = cfg.port;
    };
  };
}
```

Machine config then just enables what it needs:

```nix
# machines/frame1/default.nix
{
  homelab.services.example.enable = true;
  homelab.services.example.port = 9000;  # override default if needed
}
```

## Questions Resolved

| Question | Decision |
|----------|----------|
| Machine naming | Descriptive (`frame1`, `workstation`) |
| Workstation config | Skip for now, frame1 only |
| Service complexity | Basic configs first, enhance later |
| Secrets | agenix for production, direct config for VM testing |
| Testing approach | Docker-based VM build and run on macOS |
| VM architecture | aarch64-linux for Apple Silicon |
| TLS certificates | Let's Encrypt via Cloudflare DNS challenge |
| Local domain | `lan.kaifer.dev` → 127.0.0.1 |
