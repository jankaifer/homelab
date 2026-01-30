# Ticket 006: Setup Agenix Secrets

**Status**: DONE
**Created**: 2026-01-29
**Updated**: 2026-01-30

## Task

Configure agenix for proper secrets management:
- Add SSH public keys for encryption
- Create initial secrets (Grafana admin password, Cloudflare API token)
- Update modules to use secrets instead of hardcoded values

## Implementation Plan

1. Add SSH public keys from GitHub accounts (jankaifer, jk-cf)
2. Create encrypted secrets for Cloudflare token and Grafana password
3. Update Grafana module to support `adminPasswordFile`
4. Update server config to use agenix secrets

## Work Log

### 2026-01-30

- Added SSH keys from GitHub accounts: jankaifer (2 keys), jk-cf (1 key)
- Created encrypted secrets:
  - `cloudflare-api-token.age` - Cloudflare API token for DNS challenge
  - `grafana-admin-password.age` - Random 32-char password
- Updated `modules/services/grafana.nix`:
  - Added `adminPasswordFile` option for agenix
  - Uses `$__file{path}` syntax for Grafana's file-based password
- Updated `machines/server/default.nix`:
  - Added `age.secrets` declarations with proper ownership
  - Caddy now uses `apiTokenFile` instead of hardcoded `apiToken`
  - Grafana now uses `adminPasswordFile`
- **IMPORTANT**: Old Cloudflare token was exposed in git history - user created new token

### Notes

- VM testing: Can still use hardcoded `apiToken` and `adminPassword` if needed
- Production: Uses agenix-encrypted secrets decrypted at runtime to `/run/agenix/`
- Grafana password: `tzCRhjhumJLWZ1Si6uk1ru98xHCSLN93`
