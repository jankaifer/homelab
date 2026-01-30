# Caddy Reverse Proxy

Caddy is a modern web server with automatic HTTPS.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/caddy.nix`

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
    apiToken = "..."; # For VM testing; use apiTokenFile with agenix in production
  };
  virtualHosts = {
    "lan.kaifer.dev" = "reverse_proxy localhost:3000";
  };
};
```

## Purpose

Caddy serves as the main reverse proxy for all web services:
- Automatic HTTPS via Let's Encrypt with Cloudflare DNS challenge
- Single entry point for all HTTP/HTTPS traffic
- Real certificates work on local development (via `lan.kaifer.dev` → 127.0.0.1)

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

**DNS record:** `lan.kaifer.dev` → `127.0.0.1` (A record in Cloudflare)

## Access

| Environment | URL |
|-------------|-----|
| VM (local) | https://lan.kaifer.dev:8443 |
| Production | https://lan.kaifer.dev |

Note: VM uses port 8443 on host (mapped to 443 in VM) to avoid requiring root privileges.

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
