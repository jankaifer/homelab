# Authelia SSO

Authelia provides the homelab SSO portal, OIDC provider, and Caddy forward-auth authorization endpoint.

## Status

**Enabled:** Yes

## Configuration

**Module:** `modules/services/authelia.nix`  
**Pattern:** `homelab.services.authelia.enable`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.authelia.enable` | bool | false | Enable Authelia |
| `homelab.services.authelia.domain` | string | `auth.frame1.hobitin.eu` | Public portal domain through Caddy |
| `homelab.services.authelia.cookieDomain` | string | `frame1.hobitin.eu` | Cookie scope for protected subdomains |
| `homelab.services.authelia.defaultRedirectDomain` | string | `frame1.hobitin.eu` | Portal default redirect target |
| `homelab.services.authelia.port` | int | 9091 | Internal Authelia HTTP port |
| `homelab.services.authelia.usersFile` | path or null | null | agenix-managed file authentication database |
| `homelab.services.authelia.secrets.*` | path or null | null | agenix-managed Authelia runtime secrets |
| `homelab.services.authelia.grafana.enable` | bool | true | Register the Grafana OIDC client |
| `homelab.services.authelia.grafana.clientSecretDigest` | string or null | null | PBKDF2 digest of the Grafana client secret |
| `homelab.services.authelia.accessControlRules` | list | frame1 one-factor rules | Forward-auth access-control policy |
| `homelab.services.authelia.metrics.enable` | bool | true | Expose Prometheus metrics on loopback |

Current production wiring:

```nix
homelab.services.authelia = {
  enable = true;
  domain = "auth.frame1.hobitin.eu";
  cookieDomain = "frame1.hobitin.eu";
  defaultRedirectDomain = "frame1.hobitin.eu";
  usersFile = config.age.secrets.authelia-users.path;

  secrets = {
    jwtSecretFile = config.age.secrets.authelia-jwt-secret.path;
    sessionSecretFile = config.age.secrets.authelia-session-secret.path;
    storageEncryptionKeyFile = config.age.secrets.authelia-storage-encryption-key.path;
    oidcHmacSecretFile = config.age.secrets.authelia-oidc-hmac-secret.path;
    oidcIssuerPrivateKeyFile = config.age.secrets.authelia-oidc-issuer-private-key.path;
  };

  grafana = {
    enable = true;
    domain = "grafana.frame1.hobitin.eu";
    clientSecretDigest = "$pbkdf2-sha512$...";
  };
};
```

## Access

| Environment | URL |
|-------------|-----|
| VM (local) | https://auth.frame1.hobitin.eu:8443 |
| Production | https://auth.frame1.hobitin.eu |

Authelia listens only on `127.0.0.1:9091`; Caddy is the only public entry point.

## Secrets

Authelia uses these agenix secrets:

| Secret | Purpose |
|--------|---------|
| `authelia-jwt-secret.age` | Password-reset and identity-validation JWT signing secret |
| `authelia-session-secret.age` | Session signing/encryption secret |
| `authelia-storage-encryption-key.age` | Local storage encryption key |
| `authelia-oidc-hmac-secret.age` | OIDC token HMAC secret |
| `authelia-oidc-issuer-private-key.age` | OIDC issuer private key |
| `authelia-users.age` | File authentication user database |
| `grafana-oidc-client-secret.age` | Grafana OIDC client secret |

The initial `jankaifer` bootstrap password is stored as a comment inside `authelia-users.age`. Rotate it after the first successful login.

```bash
cd secrets
nix run github:ryantm/agenix -- -d authelia-users.age
```

## Users

Users are declared in `authelia-users.age` using Authelia's file authentication database format:

```yaml
users:
  username:
    disabled: false
    displayname: Full Name
    password: "$argon2id$..."
    email: user@example.com
    groups:
      - admins
```

To add or rotate a user password:

```bash
# Generate an Argon2 password hash.
authelia crypto hash generate argon2 --random --random.length 32 --no-confirm

# Edit the encrypted users database and replace or add the user entry.
cd secrets
nix run github:ryantm/agenix -- -e authelia-users.age
```

Groups used by the initial rollout:

| Group | Effect |
|-------|--------|
| `admins` | Grafana Admin role through OIDC |
| `grafana-editors` | Grafana Editor role through OIDC |

## Grafana OIDC

Authelia registers a `grafana` confidential OIDC client with:

- Redirect URI: `https://grafana.frame1.hobitin.eu/login/generic_oauth`
- Scopes: `openid profile groups email`
- Authorization policy: `one_factor`
- PKCE: required, `S256`
- Token endpoint auth method: `client_secret_basic`

Grafana still keeps its local admin login enabled for break-glass recovery.

To rotate the Grafana OIDC client secret:

1. Generate a new random PBKDF2 digest:
   ```bash
   authelia crypto hash generate pbkdf2 --random --random.length 48 --no-confirm
   ```
2. Store the random password in `secrets/grafana-oidc-client-secret.age`.
3. Replace `homelab.services.authelia.grafana.clientSecretDigest` with the generated digest.
4. Run `nix eval` and deploy.

## Protecting a Caddy Host

Use `homelab.services.caddy.protectedVirtualHosts` for services that should rely on Authelia forward-auth:

```nix
homelab.services.caddy.protectedVirtualHosts."app.frame1.hobitin.eu" = {
  upstream = "127.0.0.1:8080";
};
```

The helper expands to Caddy `forward_auth` against Authelia's `/api/authz/forward-auth` endpoint and copies identity headers to the upstream.

If a service needs a stricter policy, add a specific rule before the wildcard rule:

```nix
homelab.services.authelia.accessControlRules = [
  {
    domain = "admin.frame1.hobitin.eu";
    policy = "one_factor";
    subject = [ "group:admins" ];
  }
  {
    domain = "*.frame1.hobitin.eu";
    policy = "one_factor";
  }
];
```

## Backup And Restore

Back up:

- `/var/lib/authelia-main/db.sqlite3`
- `/var/lib/authelia-main/notification.txt`
- all Authelia `.age` files

The Nix configuration and agenix secrets are enough to recreate the desired identity configuration. The state directory preserves sessions, remember-me tokens, and local Authelia metadata.

## Break-Glass Recovery

Authelia must not block SSH, sudo, deploy-rs, or local Grafana admin recovery.

If Authelia is broken:

1. SSH to `frame1`.
2. Check logs:
   ```bash
   journalctl -u authelia-main -n 200 --no-pager
   ```
3. Temporarily bypass a protected Caddy host by moving it from `protectedVirtualHosts` to `virtualHosts`.
4. For Grafana, use the local `admin` account and `grafana-admin-password.age`.
5. Deploy only with deploy-rs so automatic rollback remains active.

## Links

- [Authelia Documentation](https://www.authelia.com/)
- [Authelia Caddy Integration](https://www.authelia.com/integration/proxies/caddy/)
- [Authelia Grafana OIDC Integration](https://www.authelia.com/integration/openid-connect/grafana/)
