# agenix secrets configuration
#
# This file declares which secrets exist and which keys can decrypt them.
# Secrets are age-encrypted files (*.age) in this directory.
#
# Usage:
# 1. Create/edit secrets: cd secrets && agenix -e secret-name.age
# 2. Reference in NixOS: age.secrets.secret-name.file = ./secrets/secret-name.age;
#
# See: https://github.com/ryantm/agenix
let
  # SSH public keys from lib/ssh-keys.nix
  keys = import ../lib/ssh-keys.nix;

  # Server SSH host key (for decrypting secrets on the machine)
  # This key is generated during installation by scripts/install-server.sh
  # INSTALL_SERVER_KEY_PLACEHOLDER
  server = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPlaceholderKeyWillBeReplacedDuringInstall000";

  # All user keys that can encrypt/decrypt secrets (for editing)
  userKeys = builtins.attrValues keys;

  # All keys including servers (for secrets that servers need to decrypt)
  allKeys = userKeys ++ [ server ];
in
{
  # Cloudflare API token for Caddy DNS challenge
  "cloudflare-api-token.age".publicKeys = allKeys;

  # Grafana admin password
  "grafana-admin-password.age".publicKeys = allKeys;

  # WiFi password for installer ISO (user keys only - server doesn't need this)
  "wifi-password.age".publicKeys = userKeys;
}
