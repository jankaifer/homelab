# Ticket 011: Add Tailscale Service Module

**Status**: IN_PROGRESS
**Created**: 2026-02-03
**Updated**: 2026-02-03

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

**Status:** Implementation complete, waiting for deployment and testing

**Remaining steps:**
1. User needs to be home to deploy to frame1
2. Deploy config to production: `nix run github:serokell/deploy-rs -- .#frame1 --skip-checks`
3. SSH to frame1 and run: `tailscale up --accept-routes`
4. Install Tailscale on laptop/phone
5. Verify remote access works
6. Optionally update DNS: point `home.kaifer.dev` to Tailscale IP
