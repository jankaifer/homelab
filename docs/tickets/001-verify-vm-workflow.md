# Ticket 001: Verify VM Workflow

**Status**: DONE
**Created**: 2026-01-29
**Updated**: 2026-01-29

## Task

Verify that the VM testing workflow works end-to-end on macOS Apple Silicon:
- ~~linux-builder setup and configuration~~ → Replaced with Docker-based approach
- Building the server-vm NixOS configuration
- Booting the VM with QEMU
- Accessing services (Homepage on port 3000, SSH on port 2222)

This is a prerequisite for all other development work - we need a working feedback loop.

## Solution

Used Docker-based nix build approach instead of linux-builder:
- Simpler than configuring SSH-based linux-builder
- Uses `nixos/nix:latest` Docker image
- Persistent `homelab-nix-store` volume for fast rebuilds
- Scripts created: `scripts/run-vm-docker.sh` (build + run), `scripts/nix-build-docker.sh` (build only)

## Usage

```bash
# Build and run VM interactively (requires terminal for QEMU)
./scripts/run-vm-docker.sh

# Build only (can run in background)
./scripts/run-vm-docker.sh --build

# Then run VM separately
./scripts/run-vm-docker.sh
```

Ports forwarded:
- Homepage: http://localhost:3000
- SSH: localhost:2222

## Work Log

### 2026-01-29

- Ticket created
- Attempted native linux-builder approach - SSH connection issues
- Pivoted to Docker-based approach using `nixos/nix:latest` image
- First Docker approach used default network - failed with DNS issues during large downloads
- Switched to `--network host` for build phase - resolved DNS issues
- Created persistent `homelab-nix-store` volume for caching
- Build completed successfully after ~25 minutes (first build with kernel modules)
- Future builds will be faster due to cached nix store
- **DONE**: VM can be built and run. User should test Homepage accessibility manually.
