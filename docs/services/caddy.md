# Caddy Reverse Proxy

Caddy is the reverse proxy and HTTPS termination point for web services. In production, certificates are issued by NixOS `security.acme` and loaded from `/var/lib/acme`; in VM testing, Caddy uses its internal CA.

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
| `homelab.services.caddy.cloudflareDns.enable` | bool | false | Use Cloudflare DNS challenge via `security.acme` |
| `homelab.services.caddy.cloudflareDns.apiToken` | string | null | Cloudflare API token (VM testing) |
| `homelab.services.caddy.cloudflareDns.apiTokenFile` | string | null | Path to token file (production) |
| `homelab.services.caddy.virtualHosts` | attrset | {} | Virtual host configurations |
| `homelab.services.caddy.protectedVirtualHosts` | attrset | {} | Authelia-protected reverse proxy hosts |

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
    "local.hobitin.eu" = "reverse_proxy localhost:3000";
    "frame1.hobitin.eu" = "reverse_proxy localhost:3000";
  };
};
```

## Purpose

Caddy serves as the main reverse proxy for all web services:
- Automatic HTTPS via NixOS `security.acme` and Cloudflare DNS challenge
- Single entry point for all HTTP/HTTPS traffic
- Split-horizon hostname strategy for production (`frame1.hobitin.eu`)
- Real certificates also work on local development (via `local.hobitin.eu` → 127.0.0.1)
- Optional Authelia forward-auth helper for protected upstreams

## Architecture

```
Internet → Caddy (:80/:443) → Homepage (:3000)
                            → Authelia (:9091)
                            → Grafana (:3001)
                            → Other services...
```

## Authelia Protected Hosts

For services that should use Authelia forward-auth, declare them through `protectedVirtualHosts`:

```nix
homelab.services.caddy.protectedVirtualHosts."app.frame1.hobitin.eu" = {
  upstream = "127.0.0.1:8080";
};
```

The helper expands to:

- `forward_auth 127.0.0.1:9091`
- `uri /api/authz/forward-auth`
- copied identity headers: `Remote-User`, `Remote-Groups`, `Remote-Email`, `Remote-Name`
- `reverse_proxy <upstream>`

Do not declare the same hostname in both `virtualHosts` and `protectedVirtualHosts`; the module asserts this during evaluation.

## TLS Setup

Production uses NixOS `security.acme` with Cloudflare DNS challenge:
1. `security.acme` requests one certificate per configured Caddy virtual host
2. ACME challenge credentials are derived from the shared Cloudflare secret at runtime
3. Certificates are issued into `/var/lib/acme/<domain>/`
4. Caddy loads those certificate and key paths explicitly

This keeps web TLS aligned with Mosquitto, so certificate issuance, renewal, and service reloads now follow one NixOS-native path.

Production DNS strategy (Cloudflare):
- `frame1.hobitin.eu` → frame1 Tailscale IPv4 (`100.x.y.z`)
- `*.frame1.hobitin.eu` CNAME → `frame1.hobitin.eu` (DNS-only wildcard reservation)

LAN split-horizon override (managed on router):
- `frame1.hobitin.eu` → frame1 LAN IPv4 (for local clients without Tailscale)

## Access

| Environment | URL |
|-------------|-----|
| VM (local) | https://local.hobitin.eu:8443 |
| Production (primary) | https://frame1.hobitin.eu |
| Production (compatibility) | https://local.hobitin.eu |

Note: VM uses port 8443 on host (mapped to 443 in VM) to avoid requiring root privileges. Backend services need to allow both `local.hobitin.eu` and `local.hobitin.eu:8443` in their host validation.
Wildcard note: `*.frame1.hobitin.eu` currently resolves in DNS but is not routed by Caddy in phase 1.

## Files

- `modules/services/caddy.nix` - NixOS module definition

## Dependencies

- Services to proxy (Homepage, Grafana, etc.)
- Cloudflare API token with Zone:DNS:Edit permission
- NixOS `security.acme`

## Security Notes

- For production, use `apiTokenFile` with agenix instead of `apiToken` in config
- The `apiToken` option stores the token in the nix store (visible in config)
- ACME credentials are transformed into a lego-compatible env file under `/run/` at renewal time, not kept in the Caddyfile

## Links

- [Caddy Website](https://caddyserver.com/)
- [Caddy Docs](https://caddyserver.com/docs/)
- [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
