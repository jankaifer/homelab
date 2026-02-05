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
    PermitRootLogin = "yes";      # For VM testing; tighten for production
    PasswordAuthentication = true; # For VM testing; use keys in production
  };
};

networking.firewall.allowedTCPPorts = [ 22 ];
```

## Access

| Environment | Command |
|-------------|---------|
| VM (local) | `ssh -p 2222 root@localhost` |
| VM (local) | `ssh -p 2222 admin@localhost` |
| Production | `ssh root@<server-ip>` |

**Credentials (VM only):**
- Password: `nixos`

## Security Notes

Current configuration is for VM testing only:

- Root login enabled - disable for production
- Password authentication enabled - use SSH keys for production
- Simple password - use agenix-encrypted secrets for production

### Production Hardening (TODO)

```nix
services.openssh.settings = {
  PermitRootLogin = "prohibit-password"; # or "no"
  PasswordAuthentication = false;
};

# Add SSH keys via agenix
users.users.admin.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAA... user@machine"
];
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
