# Ticket 025: Authelia SSO Foundation

**Status**: IN_PROGRESS
**Created**: 2026-03-31
**Updated**: 2026-05-01

## Task

Implement a lightweight, self-hosted SSO foundation using Authelia, managed primarily through NixOS configuration and agenix secrets. The goal is to reduce per-service credentials while keeping the operating model simple, declarative, and compatible with the existing Caddy reverse proxy.

This ticket establishes identity and access control for future protected services, especially the always-on OpenClaw personal assistant from Ticket 039.

## Implementation Plan

1. Create `modules/services/authelia.nix` following the existing `homelab.services.<name>.enable` module pattern.
2. Enable a single Authelia instance exposed at `auth.frame1.hobitin.eu` through Caddy.
3. Keep desired identity state declarative:
   - users and groups in Nix-managed Authelia file authentication
   - password hashes stored through agenix, not plaintext Nix
   - access control rules in Nix
   - OIDC clients in Nix where practical
4. Store required Authelia secrets in agenix:
   - JWT secret
   - session secret
   - storage encryption key
   - OIDC HMAC secret
   - OIDC issuer private key
   - initial user password hashes
   - Grafana OIDC client secret
   - OpenClaw/proxy OIDC or forward-auth secret if needed
5. Add a Caddy integration helper for protected virtual hosts, likely via an option on the Caddy module rather than duplicating `forward_auth` blocks in each service module.
6. Protect initial services in this order:
   - Authelia portal itself
   - Grafana using native OIDC where possible
   - OpenClaw using Caddy forward-auth once Ticket 039 is implemented
7. Keep Home Assistant on native Home Assistant auth for the first rollout. Revisit OIDC or proxy auth only after Authelia is stable.
8. Document operating procedures:
   - adding a user
   - rotating secrets
   - adding an OIDC client
   - protecting a new Caddy virtual host
   - recovery path if Authelia is broken

## Design Decision

Use Authelia rather than authentik, Keycloak, or Pocket ID.

- Authelia is the best fit for the current requirement: self-hosted, low overhead, Caddy-friendly, and mostly declarative through Nix.
- authentik is more polished as a homelab identity product, but it encourages UI/database-managed state and is less aligned with a no-clickops Nix workflow.
- Keycloak is too heavy for the current homelab scale.
- Pocket ID is attractive for passkey-first OIDC, but passkey enrollment and identity state are less aligned with the desired Nix-owned baseline.

## State Boundary

The target is "Nix-owned desired state", not literal zero state. Some runtime state is unavoidable:

- browser sessions
- remember-me tokens
- optional MFA/passkey enrollment state
- SQLite/local storage metadata

The stable configuration should still be reproducible from:

- repository Nix files
- agenix secrets
- service data backup for Authelia runtime state

## Notes

- Public exposure remains by explicit exception only. Authelia should be paired with Tailscale/VPN restrictions where practical for sensitive admin surfaces.
- Avoid making Authelia a single point of lockout for SSH, deploy-rs, or emergency recovery.
- Grafana should prefer native OIDC over only reverse-proxy auth so user identity and roles are visible inside Grafana.
- Home Assistant should not be forced through proxy auth in the first phase because its authentication model is operationally sensitive and less cleanly OIDC-native.
- Caddy remains the public reverse proxy; no new ingress stack should be introduced.

## Acceptance Criteria

- `homelab.services.authelia.enable` exists and can be enabled for `frame1` and `frame1-vm`.
- Authelia is reachable behind Caddy at the configured auth domain.
- Authelia configuration is generated declaratively from Nix and secrets are read from agenix-provided files.
- Caddy has a reusable pattern for Authelia-protected upstreams.
- Grafana can authenticate through Authelia OIDC, while local admin recovery remains possible.
- Documentation covers add-user, add-service, secret rotation, backup/restore, and break-glass recovery.
- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'` succeeds.
- VM build succeeds with `./scripts/run-vm-docker.sh --build`.
- Runtime smoke test confirms protected hosts redirect unauthenticated users to Authelia and allow authenticated access.

## Work Log

### 2026-03-31

- Ticket created from the project plan's deferred identity/SSO work.
- Kept architecture-first to avoid prematurely committing to a stack before the need is concrete.

### 2026-05-01

- Selected Authelia as the SSO foundation because it best matches the desired Nix-first, low-state, self-hosted operating model.
- Defined initial rollout boundary: Grafana native OIDC, OpenClaw behind Caddy forward-auth, Home Assistant deferred.
- Captured unavoidable state boundary and recovery requirements so SSO does not become an operational lockout risk.
- Added `modules/services/authelia.nix`, enabled Authelia on `frame1` and `frame1-vm`, and exposed it at `auth.frame1.hobitin.eu`.
- Added agenix-managed Authelia runtime secrets, the file-auth users database, and the Grafana OIDC client secret.
- Added the reusable `homelab.services.caddy.protectedVirtualHosts` helper for Authelia forward-auth protected upstreams.
- Enabled Grafana native OIDC against Authelia while keeping the local admin login available for break-glass recovery.
- Documented user management, secret rotation, adding protected hosts, backup/restore, and recovery operations.
- During VM smoke testing, tightened Grafana's Caddy upstream from `localhost` to `127.0.0.1` because Caddy initially tried `::1` while Grafana listens on IPv4 loopback.
