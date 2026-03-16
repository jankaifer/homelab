# VM-specific configuration
#
# This module adds settings needed for local VM testing:
# - Mounts host SSH keys via virtfs so agenix can decrypt secrets
# - Only included in server-vm configuration, not production
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Import qemu-vm module to get virtualisation options
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  # Share host's SSH directory into VM via virtfs/9p
  # The host path (/host-ssh) is mounted from Mac's ~/.ssh by Docker
  virtualisation.sharedDirectories = {
    hostssh = {
      source = "/host-ssh";
      target = "/mnt/host-ssh";
    };
  };

  # Tell agenix to use the host's SSH key for decryption
  # This key is mounted from the Mac via Docker -> QEMU virtfs chain
  age.identityPaths = [ "/mnt/host-ssh/id_ed25519" ];

  # VM testing should use Caddy's internal CA instead of mutating real DNS
  # records or waiting on external ACME issuance.
  homelab.services.caddy = {
    localTls = lib.mkForce true;
    cloudflareDns.enable = lib.mkForce false;
  };
}
