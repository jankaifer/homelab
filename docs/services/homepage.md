# Homepage Dashboard

Homepage is a modern, fully static, fast, secure, fully proxied dashboard with integrations for over 100 services.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/homepage.nix`

**Options:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.homepage.enable` | bool | false | Enable Homepage |
| `homelab.services.homepage.port` | int | 3000 | Port to listen on |
| `homelab.services.homepage.openFirewall` | bool | false | Open firewall port |
| `homelab.services.homepage.allowedHosts` | list | [] | Allowed hostnames for reverse proxy |

**Current settings (server):**
```nix
homelab.services.homepage = {
  enable = true;
  port = 3000;
  openFirewall = false;  # Behind Caddy
  allowedHosts = [ "local.kaifer.dev" "local.kaifer.dev:8443" ];
};
```

## Access

| Environment | URL |
|-------------|-----|
| VM (local) | https://local.kaifer.dev:8443 (via Caddy) |
| Production | https://local.kaifer.dev (via Caddy) |

## Features

- Dashboard for monitoring homelab services
- Configurable widgets and bookmarks
- Service health checks
- Clean, modern UI

## Files

- `modules/services/homepage.nix` - NixOS module definition
- Homepage config is generated from nix options (settings.yaml, services.yaml, etc.)

## Dependencies

- Caddy (reverse proxy) - Homepage is accessed through Caddy
- Other services as they're added (for status widgets)

## Decentralized Service Registration

Services register themselves on the dashboard via `homelab.homepage.services`. This allows each service module to manage its own dashboard entry without modifying the homepage module.

```nix
# Example: in your service module
homelab.homepage.services = [{
  name = "MyService";
  category = "Monitoring";  # Groups services together
  description = "Short description";
  href = "https://myservice.local.kaifer.dev:8443";
  icon = "myservice-icon";
  # widget = { ... };  # Optional widget config
}];
```

## Customization

The Homepage module generates configuration files from nix. To customize widgets or settings, edit `modules/services/homepage.nix`. Service entries are managed by individual service modules.

## Links

- [Homepage GitHub](https://github.com/gethomepage/homepage)
- [Homepage Docs](https://gethomepage.dev/)
