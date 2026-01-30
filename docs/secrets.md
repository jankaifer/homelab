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
| Cloudflare API Token | `secrets/cloudflare-api-token.age` | Caddy (DNS challenge) |
| Grafana Admin Password | `secrets/grafana-admin-password.age` | Grafana |

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

The VM setup is configured in `machines/server/vm.nix` which is only included in the `server-vm` configuration.

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

## Links

- [agenix GitHub](https://github.com/ryantm/agenix)
- [age encryption](https://age-encryption.org/)
