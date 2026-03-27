# Ticket 017: Evaluate Caddy ACME Unification with `security.acme`

**Status**: DONE
**Created**: 2026-02-08
**Updated**: 2026-03-27

## Task

Plan and evaluate migration from Caddy-managed ACME certificates to NixOS `security.acme`-managed certificates for web services.

## Implementation Plan

1. Inventory current Caddy DNS challenge flow and dependencies
2. Design target architecture using `security.acme.certs` + Caddy file paths
3. Define rollout and rollback strategy
4. Compare operational risk and cert-renewal behavior
5. Document migration steps and cutover checks

## Work Log

### 2026-02-08

- Deferred as separate follow-up by design
- Kept scope out of current smart-home implementation to avoid ingress migration risk

### 2026-03-27

- Migrated the Caddy module away from Caddy-managed DNS-challenge ACME and into NixOS `security.acme`
- Added one `security.acme.certs.<domain>` entry per configured Caddy virtual host
- Switched Caddy to load certificate and key paths from `/var/lib/acme/<domain>/`
- Added a Cloudflare credential shim for Caddy so the existing shared secret still works with lego (`CLOUDFLARE_DNS_API_TOKEN`)
- Kept VM behavior unchanged: `localTls = true` still uses Caddy's internal CA and skips ACME
- Updated Caddy and secrets documentation to reflect the unified ACME flow
- Validation:
  - `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'` passed
  - `nix eval .#nixosConfigurations.frame1.config.system.build.toplevel --apply 'x: x.drvPath'` passed
  - `./scripts/run-vm-docker.sh --build` passed
