# Ticket 002: Enable Caddy Reverse Proxy

**Status**: DONE
**Created**: 2026-01-29
**Updated**: 2026-01-30

## Task

Enable the Caddy reverse proxy module and configure it to sit in front of Homepage (and future services). The module already exists at `modules/services/caddy.nix` but is commented out in the server config.

Goals:
- Enable Caddy in server configuration
- Route traffic to Homepage through Caddy
- Prepare for future services (Grafana, etc.)

## Implementation Plan

1. **Update Caddy module** (`modules/services/caddy.nix`):
   - Add Cloudflare DNS challenge support for Let's Encrypt
   - Build Caddy with cloudflare-dns plugin
   - Support both `apiToken` (VM testing) and `apiTokenFile` (production with agenix)

2. **Update server config** (`machines/server/default.nix`):
   - Enable Caddy with Cloudflare DNS challenge
   - Configure `lan.kaifer.dev` virtual host to proxy to Homepage
   - Set Homepage's `openFirewall = false` to only allow access through Caddy

3. **Set up DNS**: Create A record `lan.kaifer.dev` → `127.0.0.1` in Cloudflare

4. **Update documentation**: caddy.md, OVERVIEW.md, PROJECT_PLAN.md

## Decisions Made

- Let's Encrypt with Cloudflare DNS challenge (real certs, no browser warnings)
- Domain: `lan.kaifer.dev` pointing to 127.0.0.1
- Homepage port 3000 closed from firewall, only accessible through Caddy
- For VM testing: API token in config (insecure but convenient)
- For production: Will use apiTokenFile with agenix

## Work Log

### 2026-01-29

- Ticket created
- Caddy module already exists, just needs to be enabled
- Awaiting planning discussion with user

### 2026-01-30

- Initial approach: self-signed certs with `tls internal`
- Hit SSL protocol error in browser, pivoted to real certs
- User chose Cloudflare DNS challenge for Let's Encrypt
- Added to Caddy module:
  - `acmeEmail` option for Let's Encrypt registration
  - `cloudflareDns.enable` to enable DNS challenge
  - `cloudflareDns.apiToken` for VM testing (direct in config)
  - `cloudflareDns.apiTokenFile` for production (agenix)
  - Build Caddy with `caddy-dns/cloudflare@v0.2.2` plugin
- Changed domain from `local.jivina.eu` to `lan.kaifer.dev`
- Created DNS A record via Cloudflare API: `lan.kaifer.dev` → `127.0.0.1`
- Updated VM script port forwarding: 8080→80, 8443→443, 2222→22
- Updated documentation:
  - `docs/services/caddy.md` - full rewrite with Cloudflare setup
  - `docs/OVERVIEW.md` - updated access URLs
  - `docs/PROJECT_PLAN.md` - replaced linux-builder with Docker workflow, marked Phase 2 complete
- VM build successful with custom Caddy package

## Summary

Caddy is now enabled as the reverse proxy with real Let's Encrypt certificates via Cloudflare DNS challenge. Access Homepage at https://lan.kaifer.dev:8443 when running the VM.
