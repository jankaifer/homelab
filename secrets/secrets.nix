# agenix secrets configuration
#
# This file declares which secrets exist and which keys can decrypt them.
# Secrets are age-encrypted files (*.age) in this directory.
#
# Usage:
# 1. Add your SSH public key(s) below
# 2. Declare secrets with which keys can access them
# 3. Create secrets: agenix -e secret-name.age
# 4. Reference in NixOS: age.secrets.secret-name.file = ./secret-name.age;
#
# See: https://github.com/ryantm/agenix
let
  # SSH public keys that can decrypt secrets
  # Add your keys here (from ~/.ssh/id_*.pub)

  # Machine keys - each server has its own key for decrypting its secrets
  # Generate with: ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key
  # server = "ssh-ed25519 AAAA... root@server";

  # User keys - for encrypting secrets from your workstation
  # admin = "ssh-ed25519 AAAA... user@workstation";

  # Placeholder until real keys are added
  # allKeys = [ server admin ];
  allKeys = [ ];
in
{
  # Example secret declarations (uncomment and adjust when ready):

  # "db-password.age".publicKeys = allKeys;
  # "grafana-admin-password.age".publicKeys = allKeys;
  # "caddy-api-token.age".publicKeys = allKeys;
}
