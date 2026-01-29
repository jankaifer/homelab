# Ticket 006: Setup Agenix Secrets

**Status**: PLANNING
**Created**: 2026-01-29
**Updated**: 2026-01-29

## Task

Configure agenix for proper secrets management:
- Add SSH public keys for encryption
- Create initial secrets (Grafana admin password, etc.)
- Update modules to use secrets instead of hardcoded values

Currently `secrets/secrets.nix` has the structure but no actual keys configured.

## Implementation Plan

[To be discussed]

## Open Questions

- Which SSH key(s) to use for encryption? (user key, machine key, both?)
- What secrets are needed initially?
  - Grafana admin password
  - Any API tokens for services
- How to handle the chicken-egg problem for new machine deployments?
- Should VM testing continue to use hardcoded passwords, or use agenix too?

## Dependencies

- Should be done after observability stack (Tickets 003-005) to know what secrets are needed
- Or can be done in parallel if we define a clear list of needed secrets

## Work Log

### 2026-01-29

- Ticket created
- secrets/secrets.nix exists with placeholder structure
- Awaiting planning discussion with user
