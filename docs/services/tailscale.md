# Tailscale VPN

Tailscale creates a secure mesh VPN using WireGuard. Enables remote access to homelab services from laptop and phone without port forwarding.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/tailscale.nix`
**Pattern:** `homelab.services.tailscale.enable`

**Options:**
| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.tailscale.enable` | bool | false | Enable Tailscale |
| `homelab.services.tailscale.acceptRoutes` | bool | false | Accept subnet routes from other nodes |
| `homelab.services.tailscale.exitNode` | bool | false | Advertise as exit node |

**Current configuration:**
```nix
homelab.services.tailscale = {
  enable = true;
};
```

## Setup

### 1. Deploy Configuration

Deploy the config to frame1:
```bash
nix run .#deploy -- .#frame1 --skip-checks
```

### 2. Authenticate Server

SSH to frame1 and run:
```bash
ssh admin@192.168.2.241
sudo tailscale up --accept-routes=false
```

Open the URL shown to authenticate via web browser.

### 3. Install Clients

**macOS:**
```bash
brew install tailscale
sudo tailscale up
```

**Linux:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

**iOS/Android:**
- Install Tailscale app from App Store / Play Store
- Sign in with same account
- Enable VPN

### 4. Find Tailscale IP

On frame1:
```bash
tailscale ip -4
# Example output: 100.x.x.x
```

Or check devices at: https://login.tailscale.com/admin/machines

### 5. Update DNS (Optional)

**Option A: Update Cloudflare DNS**

Point `home.kaifer.dev` to frame1's Tailscale IP (100.x.x.x):
- Login to Cloudflare
- DNS → A record: `home.kaifer.dev` → `100.x.x.x`
- DNS → A record: `*.home.kaifer.dev` → `100.x.x.x`

Then access services:
- https://home.kaifer.dev
- https://grafana.home.kaifer.dev
- https://metrics.home.kaifer.dev
- https://logs.home.kaifer.dev

**Option B: Use Tailscale MagicDNS**

Access via Tailscale's built-in DNS:
- `http://frame1` or `http://frame1.<tailnet>.ts.net`
- Uses Tailscale IP automatically
- No Cloudflare changes needed

**Option C: Use Tailscale IP directly**

Access via IP:
- https://100.x.x.x (if Caddy accepts IP connections)

## Access

Once Tailscale is running:

1. **Connect to Tailscale VPN** on your device.
2. **Phase 1 (current): SSH access**
   - `ssh admin@frame1.<tailnet>.ts.net` (MagicDNS)
   - `ssh admin@100.x.x.x` (direct Tailscale IP)
3. **Phase 2 (later): Web access**
   - Add Tailscale-oriented hostname strategy for Caddy/web services.
   - Then use MagicDNS or your own DNS names for HTTPS.

Services will be accessible as if you're on the local network.

## Security

- **Encrypted:** All traffic encrypted with WireGuard
- **Peer-to-peer:** Direct connections when possible (no relay)
- **No port forwarding:** Tailscale handles NAT traversal
- **Access control:** Managed via Tailscale admin console

## How It Works

```
┌──────────────┐         ┌──────────────┐
│   Laptop     │◄────────►│   frame1     │
│  (Tailscale) │  Encrypted│  (Tailscale) │
└──────────────┘  WireGuard└──────────────┘
       ▲                          ▲
       │                          │
       │     ┌──────────────┐     │
       └─────►│ Tailscale    │◄────┘
             │ Coordination │
             │   Server     │
             └──────────────┘
```

- **Coordination server:** Manages keys and NAT traversal
- **Data plane:** Direct encrypted connection (P2P)
- **Your traffic:** Never goes through Tailscale's servers

## Troubleshooting

**Check Tailscale status:**
```bash
tailscale status
```

**Check connectivity:**
```bash
tailscale ping frame1
```

**View logs:**
```bash
journalctl -u tailscaled -f
```

**Restart service:**
```bash
systemctl restart tailscaled
```

## Files

- `modules/services/tailscale.nix` - NixOS module

## Dependencies

- None (Tailscale is independent)

## Links

- [Tailscale](https://tailscale.com/)
- [Tailscale Docs](https://tailscale.com/kb/)
- [Admin Console](https://login.tailscale.com/admin)
