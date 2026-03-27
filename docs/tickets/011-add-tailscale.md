# Ticket 011: Add Tailscale Service Module

**Status**: DONE
**Created**: 2026-02-03
**Updated**: 2026-03-27

## Task

Add Tailscale VPN service to enable secure remote access to homelab services from laptop and phone. Use Tailscale SaaS (not self-hosted Headscale) for simplicity and reliability.

## Implementation Plan

1. Create `modules/services/tailscale.nix` module ✅
2. Enable Tailscale in frame1 config ✅
3. Document setup process ✅
4. Update OVERVIEW.md ✅

## Notes

- Using Tailscale SaaS for coordination (not self-hosted Headscale)
- No public IP exposure or Cloudflare tunnels
- Clients will connect via Tailscale, then access services via HTTPS
- Keep Let's Encrypt DNS challenge for TLS certificates

## Work Log

### 2026-02-03

**Completed:**

1. **Created Tailscale module** (`modules/services/tailscale.nix`)
   - Options: enable, acceptRoutes, exitNode
   - Opens firewall for Tailscale UDP port
   - Trusts tailscale0 interface
   - Enables routing features if exitNode enabled

2. **Enabled in frame1 config**
   - Imported module in machines/frame1/default.nix
   - Enabled with default settings

3. **Created documentation** (`docs/services/tailscale.md`)
   - Setup instructions (deploy, authenticate, install clients)
   - Three DNS options (Cloudflare, MagicDNS, direct IP)
   - Troubleshooting commands
   - Architecture diagram

4. **Updated OVERVIEW.md**
   - Added Tailscale to services table

**2026-03-27 validation:**
- `tailscaled` is active on `frame1`
- Tailnet IPv4 is `100.91.94.7`
- `frame1` is authenticated and reachable over Tailscale

**Status:** Complete
