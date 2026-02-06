# Caddy Reverse Proxy

Caddy is a modern web server with automatic HTTPS.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/caddy.nix`
**Pattern:** `homelab.services.caddy.enable`

**Options:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.caddy.enable` | bool | false | Enable Caddy |
| `homelab.services.caddy.acmeEmail` | string | null | Email for Let's Encrypt |
| `homelab.services.caddy.localTls` | bool | false | Use self-signed certs (quick testing) |
| `homelab.services.caddy.cloudflareDns.enable` | bool | false | Use Cloudflare DNS challenge |
| `homelab.services.caddy.cloudflareDns.apiToken` | string | null | Cloudflare API token (VM testing) |
| `homelab.services.caddy.cloudflareDns.apiTokenFile` | string | null | Path to token file (production) |
| `homelab.services.caddy.virtualHosts` | attrset | {} | Virtual host configurations |

**Current configuration:**
```nix
homelab.services.caddy = {
  enable = true;
  acmeEmail = "jan@kaifer.cz";
  cloudflareDns = {
    enable = true;
    apiTokenFile = config.age.secrets.cloudflare-api-token.path;
  };
  virtualHosts = {
    "local.kaifer.dev" = "reverse_proxy localhost:3000";
    "frame1.kaifer.dev" = "reverse_proxy localhost:3000";
  };
};
```

## Purpose

Caddy serves as the main reverse proxy for all web services:
- Automatic HTTPS via Let's Encrypt with Cloudflare DNS challenge
- Single entry point for all HTTP/HTTPS traffic
- Split-horizon hostname strategy for production (`frame1.kaifer.dev`)
- Real certificates also work on local development (via `local.kaifer.dev` → 127.0.0.1)

## Architecture

```
Internet → Caddy (:80/:443) → Homepage (:3000)
                            → Grafana (:3001)
                            → Other services...
```

## TLS Setup

Uses Cloudflare DNS challenge for Let's Encrypt certificates:
1. Caddy requests certificate from Let's Encrypt
2. Let's Encrypt asks for DNS TXT record proof
3. Caddy uses Cloudflare API to create the record
4. Certificate issued (works even for 127.0.0.1 addresses)

Production DNS strategy (Cloudflare):
- `frame1.kaifer.dev` → frame1 Tailscale IPv4 (`100.x.y.z`)
- `*.frame1.kaifer.dev` CNAME → `frame1.kaifer.dev` (DNS-only wildcard reservation)

LAN split-horizon override (managed on router):
- `frame1.kaifer.dev` → frame1 LAN IPv4 (for local clients without Tailscale)

## Access

| Environment | URL |
|-------------|-----|
| VM (local) | https://local.kaifer.dev:8443 |
| Production (primary) | https://frame1.kaifer.dev |
| Production (compatibility) | https://local.kaifer.dev |

Note: VM uses port 8443 on host (mapped to 443 in VM) to avoid requiring root privileges. Backend services need to allow both `local.kaifer.dev` and `local.kaifer.dev:8443` in their host validation.
Wildcard note: `*.frame1.kaifer.dev` currently resolves in DNS but is not routed by Caddy in phase 1.

## Files

- `modules/services/caddy.nix` - NixOS module definition

## Dependencies

- Services to proxy (Homepage, Grafana, etc.)
- Cloudflare API token with Zone:DNS:Edit permission

## Security Notes

- For production, use `apiTokenFile` with agenix instead of `apiToken` in config
- The `apiToken` option stores the token in the nix store (visible in config)

## Links

- [Caddy Website](https://caddyserver.com/)
- [Caddy Docs](https://caddyserver.com/docs/)
- [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
