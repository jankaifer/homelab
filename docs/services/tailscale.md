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
| `homelab.services.tailscale.authKeyFile` | nullOr path | null | Auth key file for unattended login |
| `homelab.services.tailscale.exitNode` | bool | false | Advertise as exit node |

**Current configuration:**
```nix
age.secrets.tailscale-auth-key = {
  file = ../../secrets/tailscale-auth-key.age;
};

homelab.services.tailscale = {
  enable = true;
  authKeyFile = config.age.secrets.tailscale-auth-key.path;
};
```

## Setup

### 1. Create Tailscale Auth Key (UI)

Open Tailscale admin console:
- Dashboard: `https://login.tailscale.com/admin`
- Keys page: `https://login.tailscale.com/admin/settings/keys`

Create an **Auth key** for server bootstrap:
- Scope: one device (`frame1`) or tagged device
- Reusable: optional (recommended for reprovisioning)
- Preauthorized: enabled (recommended for unattended setup)
- Current policy: key expires after **90 days**

### Auth Key Rotation (90-day expiry)

When the key expires, generate a new auth key in Tailscale UI and rotate the secret:
```bash
cd /Users/jankaifer/dev/jankaifer/homelab/secrets
agenix -e tailscale-auth-key.age
```

Paste the new `tskey-...` value and deploy:
```bash
cd /Users/jankaifer/dev/jankaifer/homelab
nix run .#deploy -- .#frame1 --skip-checks
```

Note: existing logged-in nodes usually stay connected. Rotation is required for reprovisioning or re-auth events.

### 2. Encrypt Auth Key into agenix Secret

Replace the placeholder secret value in `secrets/tailscale-auth-key.age`:
```bash
cd secrets
agenix -e tailscale-auth-key.age
```

Paste the raw key value (starts with `tskey-...`) and save.

### 3. Deploy Configuration

Deploy the config to frame1:
```bash
nix run .#deploy -- .#frame1 --skip-checks
```

### 4. Install Clients

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

### 5. Find Tailscale IP

On frame1:
```bash
tailscale ip -4
# Example output: 100.x.x.x
```

Or check devices at: https://login.tailscale.com/admin/machines

### 6. Update DNS (Optional)

**Option A: Update Cloudflare DNS**

Point `frame1.hobitin.eu` to frame1's Tailscale IP (100.x.x.x):
- Login to Cloudflare
- DNS → A record: `frame1.hobitin.eu` → `100.x.x.x`
- DNS → CNAME record: `*.frame1.hobitin.eu` → `frame1.hobitin.eu`

Then access services:
- https://frame1.hobitin.eu

LAN split-horizon override (UniFi/local DNS, optional but recommended):
- `frame1.hobitin.eu` → frame1 LAN IP
- Lets local clients reach services without running Tailscale

Phase-1 wildcard behavior:
- `*.frame1.hobitin.eu` resolves in DNS
- Wildcard hostnames are not yet routed by Caddy

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
2. **SSH access**
   - `ssh jankaifer@frame1.<tailnet>.ts.net` (MagicDNS)
   - `ssh jankaifer@100.x.x.x` (direct Tailscale IP)
3. **Web access (current):**
   - `https://frame1.hobitin.eu`
4. **Wildcard namespace reserved:**
   - `*.frame1.hobitin.eu` resolves, but wildcard routing is deferred

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

**Auth key login failures:**
```bash
journalctl -u tailscaled -n 100 --no-pager
```

If you see auth-key errors, re-edit `secrets/tailscale-auth-key.age` with a fresh key and redeploy.

## Files

- `modules/services/tailscale.nix` - NixOS module

## Dependencies

- None (Tailscale is independent)

## Links

- [Tailscale](https://tailscale.com/)
- [Tailscale Docs](https://tailscale.com/kb/)
- [Admin Console](https://login.tailscale.com/admin)
