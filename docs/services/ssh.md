# SSH Service

OpenSSH server for remote access and management.

## Status

**Enabled:** Yes

## Configuration

**Location:** `machines/frame1/default.nix`

**Current settings:**
```nix
services.openssh = {
  enable = true;
  settings = {
    PermitRootLogin = "no";       # Disable direct root SSH login
    PasswordAuthentication = false; # Enforce SSH key-only auth
    AllowUsers = [ "jankaifer" ]; # Restrict SSH to main operator account
  };
};

networking.firewall.allowedTCPPorts = [ 22 ];
```

## Access

| Environment | Command |
|-------------|---------|
| VM (local) | `ssh -p 2222 jankaifer@localhost` |
| Production (LAN bootstrap) | `ssh jankaifer@192.168.2.241` |
| Production (Tailscale) | `ssh jankaifer@<frame1>.<tailnet>.ts.net` |
| Production (Tailscale IP) | `ssh jankaifer@100.x.x.x` |

## Security Notes

Current production configuration is hardened:

- Root SSH login is disabled
- Password authentication is disabled
- Access is SSH key only via `jankaifer` user
- `jankaifer` has passwordless sudo for maintenance and deploy workflows

### Effective Hardening

```nix
services.openssh.settings = {
  PermitRootLogin = "no";
  PasswordAuthentication = false;
  AllowUsers = [ "jankaifer" ];
};
```

## Port Forwarding (VM)

When running the VM via Docker, SSH is forwarded:
- Container port 22 → Host port 2222

This is configured in `scripts/run-vm-docker.sh`:
```bash
QEMU_NET_OPTS="hostfwd=tcp::80-:80,hostfwd=tcp::443-:443,hostfwd=tcp::22-:22"
```

And Docker port mapping:
```bash
-p 2222:22
```

## Dependencies

None.

## Links

- [NixOS OpenSSH Options](https://search.nixos.org/options?channel=unstable&query=services.openssh)
- [OpenSSH Manual](https://man.openbsd.org/sshd_config)
