# homelab

NixOS homelab configuration with flakes, modular services, and Docker-based VM testing for macOS.

## Quick Start

```bash
# Fast evaluation check
nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'

# Build and run VM
./scripts/run-vm-docker.sh
```

## Documentation

- `docs/OVERVIEW.md` - Current architecture and enabled services
- `docs/PROJECT_PLAN.md` - Roadmap and workflow conventions
- `AGENTS.md` - Canonical coding-agent instructions (Codex-first)
- `CLAUDE.md` - Compatibility pointer to `AGENTS.md`
