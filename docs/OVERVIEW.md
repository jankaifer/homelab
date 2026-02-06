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
│  │  *.local.kaifer.dev│  (TLS via Cloudflare DNS challenge)                   │
│  └────────┬─────────┘                                                       │
│           │                                                                 │
│  ┌────────▼────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │    Homepage     │  │     Grafana     │  │ VictoriaMetrics │              │
│  │local.kaifer.dev   │  │grafana.local... │  │metrics.local... │              │
│  │ (internal:3000) │  │ (internal:3001) │  │ (internal:8428) │              │
│  └─────────────────┘  └────────┬────────┘  └────────┬────────┘              │
│                                │ queries            │ scrapes               │
│                       ┌────────▼────────┐  ┌────────▼────────┐              │
│                       │      Loki       │  │  node_exporter  │              │
│                       │ logs.local...    │  │   (port 9100)   │              │
│                       │ (internal:3100) │  └─────────────────┘              │
│                       └────────▲────────┘                                   │
│                                │ pushes                                     │
│                       ┌────────┴────────┐                                   │
│                       │     Alloy       │                                   │
│                       │ (journal logs)  │                                   │
│                       └─────────────────┘                                   │
│                                                                             │
│  ┌─────────────────┐                                                        │
│  │      SSH        │  (port 22)                                             │
│  └─────────────────┘                                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Machine Configurations

| Machine | Architecture | Purpose |
|---------|--------------|---------|
| `frame1` | x86_64-linux | Production deployment |
| `frame1-vm` | aarch64-linux | Local testing on Apple Silicon |
| `installer-iso` | x86_64-linux | Bootable ISO for server installation |

## Enabled Services

| Service | Port | URL | Documentation |
|---------|------|-----|---------------|
| Caddy | 80/443 | (reverse proxy) | [docs/services/caddy.md](services/caddy.md) |
| Homepage | 3000 (internal) | https://local.kaifer.dev | [docs/services/homepage.md](services/homepage.md) |
| Grafana | 3001 (internal) | https://grafana.local.kaifer.dev | [docs/services/grafana.md](services/grafana.md) |
| VictoriaMetrics | 8428 (internal) | https://metrics.local.kaifer.dev | [docs/services/victoriametrics.md](services/victoriametrics.md) |
| Loki | 3100 (internal) | https://logs.local.kaifer.dev | [docs/services/loki.md](services/loki.md) |
| Alloy | 12345 (internal) | (telemetry collector) | [docs/services/alloy.md](services/alloy.md) |
| Tailscale | 41641 (UDP) | (VPN mesh network) | [docs/services/tailscale.md](services/tailscale.md) |
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
nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'

# Build and run VM
./scripts/run-vm-docker.sh

# Access services (VM testing with port 8443)
# Homepage: https://local.kaifer.dev:8443
# Grafana: https://grafana.local.kaifer.dev:8443
# VictoriaMetrics: https://metrics.local.kaifer.dev:8443
# Loki: https://logs.local.kaifer.dev:8443
# SSH: ssh -p 2222 root@localhost
```

## Directory Structure

```
homelab/
├── flake.nix              # Main entry point, defines machines
├── lib/
│   └── ssh-keys.nix       # SSH public keys (shared by agenix and ISO)
├── machines/
│   ├── installer-iso/     # Bootable installer ISO
│   │   └── default.nix
│   └── frame1/
│       ├── default.nix    # frame1 config (services, users, etc.)
│       ├── disko.nix      # Declarative disk partitioning
│       ├── hardware.nix   # Hardware-specific settings
│       └── vm.nix         # VM-specific config (agenix via host SSH)
├── modules/
│   └── services/          # Reusable service modules
│       ├── alloy.nix
│       ├── caddy.nix
│       ├── grafana.nix
│       ├── homepage.nix
│       ├── loki.nix
│       └── victoriametrics.nix
├── secrets/               # agenix encrypted secrets
├── scripts/               # Development scripts
│   ├── build-installer-iso.sh  # Build bootable installer ISO
│   ├── install-server.sh       # Install NixOS on new hardware
│   ├── run-vm-docker.sh        # Build and run VM
│   └── nix-build-docker.sh
├── AGENTS.md              # Canonical coding-agent instructions (Codex-first)
├── CLAUDE.md              # Compatibility pointer to AGENTS.md
└── docs/
    ├── OVERVIEW.md        # This file
    ├── PROJECT_PLAN.md    # Future plans
    ├── secrets.md         # Secrets management guide
    ├── services/          # Per-service documentation
    └── tickets/           # Task tracking
```

## Production Installation

To install on new server hardware:

```bash
# Option 1: Custom installer ISO (headless, no keyboard needed)
./scripts/build-installer-iso.sh    # Build ISO with WiFi pre-configured
# Flash to USB, boot server, SSH in, then run nixos-anywhere

# Option 2: Standard NixOS ISO
# 1. Boot target from NixOS minimal ISO
# 2. Get target IP and set root password on installer
# 3. Run from your local machine:
./scripts/install-server.sh <target-ip>
```

See [Installation Guide](services/installation.md) and [Installer ISO](services/installer-iso.md) for details.

## Production Deployment

### Overview

The homelab uses **deploy-rs** for safe, automated deployments with automatic rollback protection. Builds happen on your Mac (aarch64-darwin) but delegate x86_64-linux compilation to frame1 via remote builders.

### Deployment Architecture

```
┌─────────────────┐         SSH Builder         ┌─────────────────┐
│   Mac (dev)     │────────────────────────────▶│  frame1 (x86)   │
│ aarch64-darwin  │  Delegates x86_64 builds    │  x86_64-linux   │
└────────┬────────┘                             └────────┬────────┘
         │                                               │
         │ 1. Trigger deploy                             │ 2. Build closure
         │ 3. Copy closure ────────────────────────────▶ │
         │ 4. Activate + confirm ◀───────────────────────┤
         │ 5. Rollback if fail                           │
         └───────────────────────────────────────────────┘
```

### How It Works

1. **Build Phase**
   - Mac triggers `nix build` for frame1 configuration
   - Nix detects x86_64-linux derivations and delegates to remote builder
   - frame1 builds the system closure natively
   - Built closure copied back to Mac's nix store

2. **Deploy Phase**
   - deploy-rs copies the closure to frame1 via SSH
   - Activates new configuration with systemd switch
   - Waits for confirmation (30 second timeout)

3. **Confirmation**
   - If activation succeeds and SSH remains stable → confirmed
   - If activation fails, SSH breaks, or timeout expires → **automatic rollback**

### Deploy Commands

```bash
# Set up PATH (needed for deploy-rs)
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Deploy to frame1 (production)
nix run .#deploy -- .#frame1 --skip-checks

# Test without activating (dry run)
nix run .#deploy -- .#frame1 --dry-activate

# Deploy to VM for testing (localhost:2222)
nix run .#deploy -- .#frame1-vm --skip-checks
```

**Note:** `--skip-checks` is needed because deploy-rs checks require aarch64-linux builders (for frame1-vm config), which aren't available on Mac.

### Remote Builder Setup

frame1 acts as a remote builder for x86_64-linux:

**On Mac (`/etc/nix/nix.custom.conf`):**
```
builders-use-substitutes = true
trusted-users = jankaifer

# Reference to builders file
builders = @/etc/nix/machines
```

**Builder configuration (`/etc/nix/machines`):**
```
ssh://admin@192.168.2.241 x86_64-linux - 4 1 big-parallel,benchmark
```

This allows your Mac to seamlessly build x86_64-linux packages by delegating to frame1.

### Safety Features

**Magic Rollback:**
- Automatically reverts if activation fails
- Protects against SSH breakage
- Guards against service failures
- 30-second confirmation window

**Health Checks:**
- Systemd activation verification
- SSH connectivity validation
- Network connectivity preserved

**Atomic Deployments:**
- New configuration built as complete closure
- Old configuration preserved and bootable
- Switch happens atomically via systemd-switch-to-configuration

### Deployment Workflow

```bash
# 1. Make configuration changes
vim machines/frame1/default.nix

# 2. Optional: Validate syntax (fast, no build)
nix eval .#nixosConfigurations.frame1.config.system.build.toplevel --apply 'x: x.drvPath'

# 3. Optional: Build locally to catch errors early
nix build .#nixosConfigurations.frame1.config.system.build.toplevel

# 4. Deploy to production
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
nix run .#deploy -- .#frame1 --skip-checks

# 5. Verify services
ssh admin@192.168.2.241 "systemctl status caddy grafana"
curl -k https://local.kaifer.dev
```

### Secrets Management

Secrets are encrypted with **agenix** and automatically decrypted during deployment:

- Secrets stored in `secrets/*.age` (encrypted with age)
- Decrypted to `/run/agenix/*` at boot time
- Uses SSH keys for encryption (defined in `secrets/secrets.nix`)
- frame1's SSH host key included in secret recipients

See [docs/secrets.md](secrets.md) for details.

### Rollback

If a deployment causes issues:

```bash
# Automatic rollback already happened if activation failed
# But you can manually rollback if needed:

ssh admin@192.168.2.241
sudo nixos-rebuild switch --rollback

# Or reboot to previous generation (grub menu)
reboot
```

### Multi-Machine Future

The deployment setup supports multiple machines:

```nix
# Future: Deploy to all machines
nix run .#deploy

# Future: Deploy to specific machines
nix run .#deploy -- .#frame1 .#frame2 .#raspberry-pi
```

Weak devices (Raspberry Pi, etc.) will receive pre-built closures from frame1, avoiding slow local builds.

## Next Steps

See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the roadmap and [tickets/](tickets/) for active tasks.
