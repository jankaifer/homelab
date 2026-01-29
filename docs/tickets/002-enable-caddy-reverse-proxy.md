# Ticket 002: Enable Caddy Reverse Proxy

**Status**: PLANNING
**Created**: 2026-01-29
**Updated**: 2026-01-29

## Task

Enable the Caddy reverse proxy module and configure it to sit in front of Homepage (and future services). The module already exists at `modules/services/caddy.nix` but is commented out in the server config.

Goals:
- Enable Caddy in server configuration
- Route traffic to Homepage through Caddy
- Prepare for future services (Grafana, etc.)

## Implementation Plan

[To be discussed]

## Open Questions

- Should Caddy listen on port 80 only, or also 443 with self-signed certs for VM testing?
- Should Homepage firewall port be closed once Caddy is in front?
- What domain/host pattern to use for VM testing? (`:80`, `localhost`, etc.)

## Work Log

### 2026-01-29

- Ticket created
- Caddy module already exists, just needs to be enabled
- Awaiting planning discussion with user
