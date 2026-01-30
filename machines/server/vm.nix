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

  # Ensure agenix waits for the SSH key mount before decrypting secrets
  # The mount unit name is derived from the mount path: mnt-host\x2dssh.mount
  systemd.services.agenix.after = [ "mnt-host\\x2dssh.mount" ];
  systemd.services.agenix.requires = [ "mnt-host\\x2dssh.mount" ];
}
