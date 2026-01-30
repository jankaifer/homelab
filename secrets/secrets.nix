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
  # SSH public keys from GitHub accounts (can decrypt secrets)
  # jankaifer
  jankaifer-1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJe9IWxd3nIG9qm86UMTZeVHHeHN5eh6nHu7KwU+x/fz";
  jankaifer-2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQZcA7EKUH91Sp4s2aRNJ6sOgZCUx9CqDuaEiPvWjWC";
  # jk-cf
  jk-cf = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG6x4L/uYrM/KmYBTvvl3FaO2T3T5Vf+uAnEKKA43BwU";

  # All user keys that can encrypt/decrypt secrets
  allKeys = [ jankaifer-1 jankaifer-2 jk-cf ];
in
{
  # Cloudflare API token for Caddy DNS challenge
  "cloudflare-api-token.age".publicKeys = allKeys;

  # Grafana admin password
  "grafana-admin-password.age".publicKeys = allKeys;
}
