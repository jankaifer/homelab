# Ticket 009: Deployment Strategy

**Status**: DONE
**Created**: 2026-02-02
**Updated**: 2026-02-03

## Task

Determine the optimal deployment strategy for the NixOS homelab. Key questions:
- Where should builds happen? (macOS dev machine vs. target server)
- What tooling should we use? (nixos-rebuild, deploy-rs, colmena, etc.)
- How do we handle the build environment constraints on macOS?

## Options Analysis

### Option 1: Build on macOS, Deploy to Target

**How it works:**
- Use `nix build` with cross-compilation or remote builder
- Push the built closure to the target via `nix copy`
- Activate on the target with `nixos-rebuild switch`

**Pros:**
- Fast iteration - use your powerful Mac
- Can work offline (build locally, deploy later)
- No load on the target during builds

**Cons:**
- Cross-compilation complexity (x86_64-linux on aarch64-darwin)
- Requires a Linux builder (Docker, remote machine, or nix-darwin linux-builder)
- Larger network transfer (full closures)

### Option 2: Build on Target

**How it works:**
- Push config changes to git or directly to target
- Run `nixos-rebuild switch` on the target itself

**Pros:**
- Simple - native builds, no cross-compilation
- No builder setup needed
- Works even if Mac is offline

**Cons:**
- Slower builds (server hardware vs Mac)
- Server load during builds
- Need SSH access during deployment

### Option 3: Remote Builder (Hybrid)

**How it works:**
- macOS triggers builds but delegates to a remote Linux builder
- Could be the target itself, a dedicated build server, or a cloud builder

**Pros:**
- Best of both worlds
- Native Linux builds
- Can use target as its own builder

**Cons:**
- More setup complexity
- Need to maintain builder configuration

### Option 4: Deployment Tools (deploy-rs, colmena)

**How it works:**
- Use specialized NixOS deployment tools
- These handle building, copying, and activation

**Pros:**
- Atomic deployments with rollback
- Multi-machine orchestration
- Built-in safety features (health checks, rollback on failure)

**Cons:**
- Additional tooling to learn
- May be overkill for single-machine homelab

## Current State

- Building in Docker on macOS (slow, for VM testing only)
- No production deployment workflow yet
- Target is x86_64-linux, dev machine is aarch64-darwin (Apple Silicon)

## Requirements (from discussion)

- **Multi-machine**: Will manage multiple NixOS machines
- **Weak devices**: Some targets can't build locally (e.g., Raspberry Pi, small NUCs)
- **Automatic rollback**: Deploy failures MUST roll back automatically
- **Safe remote deploys**: Can't risk bricking a remote machine

## Refined Analysis

Given these requirements, **Option 2 (build on target)** is eliminated - weak devices can't build.

This leaves us choosing between deployment tools. The main contenders:

### deploy-rs

- Written in Rust, maintained by Serokell
- **Magic rollback**: If the new config breaks SSH/activation, auto-reverts
- Simple flake integration
- Supports `--dry-activate` for testing
- Good for 1-20 machines

### colmena

- Written in Rust, inspired by NixOps
- Similar rollback capabilities
- Better for larger fleets (parallel deploys, tags)
- More features (secrets, node targeting)
- Slightly more complex config

### nixos-rebuild (with limitations)

- Built-in `--rollback` but NOT automatic
- No health checks
- Simpler but doesn't meet the "auto rollback on failure" requirement

## Recommendation: deploy-rs

For your use case, **deploy-rs** is the best fit:

1. **Magic rollback** - If activation fails or SSH breaks, it reverts automatically
2. **Simple** - Minimal config, integrates cleanly with your existing flake
3. **Proven** - Widely used in the NixOS community
4. **Build anywhere** - You build on Mac (with Linux builder) or a build server, deploy-rs just copies and activates

### How deploy-rs rollback works

```
1. Build closure on build machine
2. Copy closure to target
3. Activate new config with a "confirm" timeout
4. If target doesn't confirm within timeout → auto rollback
5. If SSH breaks → can't confirm → auto rollback
6. If activation crashes → auto rollback
```

This is exactly what you need for safe remote deploys.

## Remaining Question: Build Strategy

deploy-rs handles deployment, but we still need to build x86_64-linux on your Mac. Options:

| Method | Setup Effort | Speed | Reliability |
|--------|-------------|-------|-------------|
| **nix-darwin linux-builder** | Medium | Good | Good |
| **Use server as remote builder** | Low | Good | Needs server online |
| **GitHub Actions** | Medium | Varies | Good for CI |
| **Docker builder** | Already have | Slow | Works |

**My suggestion**: Use your main server as a remote builder. It's already x86_64-linux, and you need it online to deploy anyway. Weak devices get pre-built closures pushed to them.

## Implementation Plan

### Naming
- Main server renamed from `server` to `frame1`
- VM testing config: `frame1-vm` (was `server-vm`)

### Phase 1: Rename server → frame1
1. Rename `machines/server/` → `machines/frame1/`
2. Update flake.nix nixosConfigurations
3. Update all references in docs and scripts
4. Test with `nix eval`

### Phase 2: Add deploy-rs
1. Add deploy-rs as flake input
2. Configure deploy node for frame1
3. Set up magic rollback with appropriate timeout
4. Test deployment workflow

### Phase 3: Remote Builder Setup
1. Configure frame1 as a remote builder in nix.conf
2. Set up SSH keys for builder access
3. Test cross-machine builds from Mac

### Phase 4: Documentation
1. Update CLAUDE.md with new deployment workflow
2. Document deploy-rs usage
3. Update OVERVIEW.md with new machine name

## Work Log

### 2026-02-02

- Created ticket to discuss deployment options
- Listed four main approaches with pros/cons
- User clarified: multi-machine, weak devices, MUST have auto-rollback
- Narrowed recommendation to deploy-rs with server as remote builder
- User agreed on deploy-rs approach
- Renamed main server: `server` → `frame1`
- Agreed implementation plan: rename first, then add deploy-rs, then remote builder setup

**Phase 1 Complete: Rename server → frame1**
- Renamed `machines/server/` → `machines/frame1/`
- Updated flake.nix: `server` → `frame1`, `server-vm` → `frame1-vm`
- Updated machine config: hostname `server` → `frame1`
- Updated all documentation: CLAUDE.md, OVERVIEW.md, PROJECT_PLAN.md
- Updated all scripts: install-server.sh, run-vm-docker.sh
- Updated secrets.nix: `server` key → `frame1`
- Validated both configurations successfully with nix eval

**Phase 2 Complete: Add deploy-rs**
- Added deploy-rs as flake input with nixpkgs follows
- Configured deploy.nodes.frame1 with:
  - hostname: frame1.local (placeholder, user should update)
  - sshUser: root
  - Magic rollback enabled
  - Auto-rollback enabled
  - 30-second confirmation timeout
- Added deploy.nodes.frame1-vm for VM testing
- Added deploy-rs checks to flake outputs
- Updated flake.lock with deploy-rs
- Updated CLAUDE.md with deployment workflow section
- Updated OVERVIEW.md with production deployment section
- Validated configuration after changes
- Tested deployment: deploy-rs works correctly, but confirmed need for remote builder (Phase 3) to build aarch64-linux from macOS

**Phase 3 Complete: Remote Builder Setup + Production Deployment**
- Configured frame1 (192.168.2.241) as remote builder for x86_64-linux
- Added builder configuration to /etc/nix/machines
- Added jankaifer to trusted-users in /etc/nix/nix.custom.conf
- Shared SSH keys with root user for builder authentication
- Tested remote builder: Mac successfully delegates x86_64-linux builds to frame1
- Deployed to production frame1 using deploy-rs
- Magic rollback verified working (rolled back 3 times during debugging)
- Hostname successfully changed to "frame1" on production
- All services running successfully

**Caddy Cloudflare Integration Fixed**
- Initial deployment failed: Caddy getting HTTP 403 "Invalid access token" from Cloudflare
- Root cause: Old Cloudflare API token from git history was expired/invalid
- User provided new token: u4QudqJpCp-___2-Diujtr-otULnPYWhra1ZLT4l
- Re-encrypted cloudflare-api-token.age with new token using age
- Second issue: Token missing Zone:Zone:Read permission (only had Zone:DNS:Edit)
- User updated token permissions in Cloudflare dashboard to include:
  - Zone:Zone:Read ✓
  - Zone:DNS:Edit ✓
- Deployed updated secret to frame1
- Restarted Caddy service
- Caddy successfully obtained Let's Encrypt certificates via Cloudflare DNS-01 challenge
- Verified certificates for all domains:
  - lan.kaifer.dev ✓
  - grafana.lan.kaifer.dev ✓
  - logs.lan.kaifer.dev ✓
  - metrics.lan.kaifer.dev ✓
- Verified HTTPS working: HTTP/2 200 response from https://lan.kaifer.dev

### 2026-02-03

**Deployment Complete!**

The deployment infrastructure is fully operational:
- ✅ deploy-rs with magic rollback
- ✅ frame1 as remote builder for x86_64-linux
- ✅ Production deployment successful
- ✅ All services running including Caddy with Let's Encrypt certificates
- ✅ HTTPS working with valid certificates from Let's Encrypt

**Next steps** (future work, not part of this ticket):
- Consider adding more machines to the deployment
- Document backup/restore procedures
- Set up monitoring for certificate renewal
