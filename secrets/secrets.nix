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

  # frame1 SSH host key (for decrypting secrets on the machine)
  # This key is generated during installation by scripts/install-server.sh
  # INSTALL_SERVER_KEY_PLACEHOLDER
  frame1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBoqYtWVI6OsrnGoc7t6LgItSpsRZJx/3W3mFUXtSf+1";

  # All user keys that can encrypt/decrypt secrets (for editing)
  userKeys = builtins.attrValues keys;

  # All keys including servers (for secrets that servers need to decrypt)
  allKeys = userKeys ++ [ frame1 ];
in
{
  # Cloudflare API token for Caddy DNS challenge
  "cloudflare-api-token.age".publicKeys = allKeys;

  # Grafana admin password
  "grafana-admin-password.age".publicKeys = allKeys;

  # Tailscale auth key for unattended server login
  "tailscale-auth-key.age".publicKeys = allKeys;

  # Home Assistant admin password created during onboarding
  "homeassistant-admin-password.age".publicKeys = allKeys;

  # MQTT password for Home Assistant MQTT client
  "mqtt-homeassistant-password.age".publicKeys = allKeys;

  # MQTT password for Zigbee2MQTT MQTT client
  "mqtt-zigbee2mqtt-password.age".publicKeys = allKeys;

  # MQTT password for Frigate MQTT client
  "mqtt-frigate-password.age".publicKeys = allKeys;

  # MQTT password for evcc MQTT client
  "mqtt-evcc-password.age".publicKeys = allKeys;

  # Admin password for evcc UI
  "evcc-admin-password.age".publicKeys = allKeys;

  # Tesla vehicle API credentials for evcc
  "evcc-tesla.env.age".publicKeys = allKeys;

  # Tessie no-wake Tesla telemetry credentials for evcc
  "evcc-tessie.env.age".publicKeys = allKeys;

  # MQTT password for EOS Connect MQTT client
  "mqtt-eos-connect-password.age".publicKeys = allKeys;

  # Victron Einstein GX MQTT password
  "victron-einstein-mqtt-password.age".publicKeys = allKeys;

  # Frigate camera2 RTSP URLs
  "frigate-camera2-detect-url.age".publicKeys = allKeys;
  "frigate-camera2-record-url.age".publicKeys = allKeys;

  # Frigate email notification SMTP relay settings
  "frigate-notifier-smtp-env.age".publicKeys = allKeys;

  # Restic repository password
  "restic-password.age".publicKeys = allKeys;

  # Restic repository location and object-store credentials
  "restic-repository-env.age".publicKeys = allKeys;

  # SMB password for jankaifer NAS access
  "nas-jankaifer-password.age".publicKeys = allKeys;

  # SMB password for guest NAS access
  "nas-guest-password.age".publicKeys = allKeys;
}
