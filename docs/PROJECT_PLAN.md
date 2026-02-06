# Homelab Project Plan

## Overview

NixOS-based homelab configuration with flakes. Optimized for coding-agent assisted development with a fast feedback loop via VM testing.

## Long-Term North Star

A practical, family-usable, private-first homelab on a small bare-metal fleet, operated by one person with low operational overhead.

The system prioritizes reproducibility, backup/recovery, and stable day-to-day use over high-complexity orchestration.

## End-Game Shape

1. Small fleet, typically 2-4 nodes.
2. Three core roles:
   - Main server (majority of services)
   - Dedicated Home Assistant/MQTT node
   - Dedicated NAS/storage node
3. Option to add specialized nodes later when justified by a concrete workload.
4. No Kubernetes platform.
5. No Proxmox VM-hosting platform.
6. No strict HA target; best-effort reliability with fast recovery.

## Operating Principles

1. Infrastructure as code with NixOS flakes remains the control plane.
2. Scheduled, predictable deployments with rollback safety.
3. Private-by-default access; public exposure only by explicit exception.
4. Data-first practical security:
   - Strong protection for important data and secrets
   - Avoid enterprise-heavy hardening overhead where it does not add proportional value
5. Progressive network segmentation is in scope, especially for IoT and smart-home isolation.

## Data and Backup Strategy

1. Backup by default for almost all data.
2. Tier-1 (default): 3-2-1 backups with encrypted cloud offsite copy.
3. Tier-2 (explicit exceptions): no-backup, easy-rebuild data only.
4. Current disposable examples:
   - Movies and media libraries
   - Linux ISO collections
   - Build artifacts and similar reproducible outputs
5. Restore capability is a first-class requirement, not just backup existence.

## Access and Identity Direction

1. Mixed exposure model with public-by-exception policy.
2. Household/family usage is a primary audience.
3. Centralized SSO/auth is a long-term target as service count grows.
4. Alerting primary channel: email.

## Long-Term Service Portfolio

In scope:
1. Personal cloud services (files/photos/documents)
2. Smart-home platform (Home Assistant + MQTT direction)
3. Password vault service
4. Camera/NVR stack

Maybe later:
1. Media stack
2. DNS filtering/ad-blocking
3. Dev platform services
4. Local authoritative DNS/service discovery

Out of scope for now:
1. General workflow automation platform (n8n/Node-RED class)
2. Wiki/knowledge-base platform as a roadmap objective

## Capability Horizons

Now:
1. Harden backup/restore implementation and policy enforcement.
2. Stabilize core 3-role architecture foundations.
3. Keep deployment/update process predictable and reversible.

Next:
1. Expand family-grade service reliability and operations hygiene.
2. Introduce segmentation where it reduces risk.
3. Add identity/SSO and mature access patterns.

Later:
1. Broaden self-hosted app portfolio as operational capacity allows.
2. Add specialized nodes only when workload-specific value is clear.

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
├── AGENTS.md               # Canonical coding-agent instructions (Codex-first)
└── CLAUDE.md               # Compatibility pointer to AGENTS.md
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

## Agent Development Workflow

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
- Homepage (via Caddy): https://local.kaifer.dev:8443
- SSH: `ssh -p 2222 root@localhost` (password: `nixos`)

**Exit QEMU:** Press `Ctrl+A, X`

## Execution History (Completed Foundations)

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
| Local domain | `local.kaifer.dev` → 127.0.0.1 |
