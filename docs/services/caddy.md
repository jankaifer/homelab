# Caddy Reverse Proxy

Caddy is a modern web server with automatic HTTPS.

## Status

**Enabled:** No (module defined, not enabled)

## Configuration

**Module:** `modules/services/caddy.nix`

**Options:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.caddy.enable` | bool | false | Enable Caddy |
| `homelab.services.caddy.virtualHosts` | attrset | {} | Virtual host configurations |

**Example configuration (not yet enabled):**
```nix
homelab.services.caddy = {
  enable = true;
  virtualHosts = {
    ":80" = "reverse_proxy localhost:3000";
  };
};
```

## Purpose

Caddy will serve as the main reverse proxy for all web services:
- Automatic HTTPS with Let's Encrypt
- Single entry point for all HTTP/HTTPS traffic
- Easy virtual host configuration

## Planned Architecture

```
Internet → Caddy (:80/:443) → Homepage (:3000)
                            → Grafana (:3001)
                            → Other services...
```

## Access

| Environment | URL |
|-------------|-----|
| VM (local) | http://localhost:80 |
| Production | https://homelab.example.com |

## Files

- `modules/services/caddy.nix` - NixOS module definition

## Enabling

To enable Caddy, uncomment in `machines/server/default.nix`:

```nix
homelab.services.caddy = {
  enable = true;
  virtualHosts = {
    ":80" = "reverse_proxy localhost:3000";
  };
};
```

Also update firewall to allow ports 80 and 443.

## Dependencies

- Services to proxy (Homepage, Grafana, etc.)

## Links

- [Caddy Website](https://caddyserver.com/)
- [Caddy Docs](https://caddyserver.com/docs/)
