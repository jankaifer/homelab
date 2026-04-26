# Secrets Management

Secrets are managed using [agenix](https://github.com/ryantm/agenix) - age-encrypted secrets for NixOS.

## How It Works

1. Secrets are encrypted with SSH public keys (yours)
2. Encrypted `.age` files are committed to git (safe)
3. At deployment, the machine decrypts secrets using its SSH private key
4. Secrets are available at `/run/agenix/<secret-name>`

## Current Secrets

| Secret | File | Used By |
|--------|------|---------|
| Cloudflare API Token | `secrets/cloudflare-api-token.age` | Caddy and Mosquitto ACME |
| Grafana Admin Password | `secrets/grafana-admin-password.age` | Grafana |
| Tailscale Auth Key | `secrets/tailscale-auth-key.age` | Tailscale unattended login |
| MQTT Password (`homeassistant`) | `secrets/mqtt-homeassistant-password.age` | Home Assistant MQTT client |
| MQTT Password (`zigbee2mqtt`) | `secrets/mqtt-zigbee2mqtt-password.age` | Zigbee2MQTT MQTT client |
| MQTT Password (`frigate`) | `secrets/mqtt-frigate-password.age` | Frigate MQTT client |
| Victron Einstein MQTT Password | `secrets/victron-einstein-mqtt-password.age` | Victron GX local MQTT broker on `einstein` / `192.168.2.31` |
| Frigate Notifier Env | `secrets/frigate-notifier-smtp-env.age` | Frigate email fallback and optional ntfy push notifications |
| NAS SMB Password (`jankaifer`) | `secrets/nas-jankaifer-password.age` | Samba login for admin NAS access |
| NAS SMB Password (`nasguest`) | `secrets/nas-guest-password.age` | Samba login for guest media access |
| Restic Password | `secrets/restic-password.age` | Restic backup job |
| Restic Repository Env | `secrets/restic-repository-env.age` | Restic repository URL and object-store credentials |

## Encryption Keys

Secrets are encrypted with SSH keys from GitHub accounts:
- `jankaifer` (2 keys)
- `jk-cf` (1 key)

Keys are defined in `secrets/secrets.nix`.

## VM Testing vs Production

Both VM and production now use agenix secrets. The difference is which SSH key is used for decryption:

**VM Testing:**
- Your Mac's `~/.ssh` is mounted into the VM via Docker → QEMU virtfs chain
- agenix decrypts secrets using your host SSH key (`~/.ssh/id_ed25519`)
- No hardcoded secrets needed

**Production:**
- Server uses its own SSH host key for decryption
- Add server's SSH public key to `secrets/secrets.nix` and re-encrypt: `agenix -r`

The VM setup is configured in `machines/frame1/vm.nix` which is only included in the `frame1-vm` configuration.

## Managing Secrets

### Creating/Editing a Secret

```bash
cd secrets

# Create or edit (opens $EDITOR)
agenix -e secret-name.age

# Or encrypt directly
echo "my-secret-value" | age -r "ssh-ed25519 AAAA..." -o secret-name.age
```

### Adding a New Secret

1. Add the secret declaration to `secrets/secrets.nix`:
```nix
"new-secret.age".publicKeys = allKeys;
```

2. Create the encrypted file:
```bash
cd secrets && agenix -e new-secret.age
```

3. Reference in NixOS config:
```nix
age.secrets.new-secret = {
  file = ../../secrets/new-secret.age;
  owner = "service-user";
};
```

### Re-encrypting After Key Changes

If keys change in `secrets.nix`:
```bash
cd secrets && agenix -r
```

## Production Deployment

For production, you need to:

1. Add the server's SSH host public key to `secrets/secrets.nix`
2. Re-encrypt secrets: `agenix -r`
3. Uncomment `age.secrets` in server config
4. Switch to `apiTokenFile`/`adminPasswordFile`

## Cloudflare Secret Format

The shared Cloudflare secret can continue to expose `CLOUDFLARE_API_TOKEN=...`.

Both Caddy's web certificates and Mosquitto's MQTT certificate now derive the lego-specific `CLOUDFLARE_DNS_API_TOKEN` value from that same secret at runtime, so you do not need separate Cloudflare secrets per service.

## Restic Secret Format

`restic-password.age` should contain only the repository password.

`restic-repository-env.age` should contain an EnvironmentFile-compatible set of variables, for example:

```bash
RESTIC_REPOSITORY=s3:s3.amazonaws.com/my-homelab-bucket/frame1
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_DEFAULT_REGION=eu-central-1
```

See [restic-repository.env.example](/Users/jankaifer/dev/jankaifer/homelab/secrets/restic-repository.env.example) for the committed template.

## Links

- [agenix GitHub](https://github.com/ryantm/agenix)
- [age encryption](https://age-encryption.org/)
