# Hardware configuration for server
#
# For VM testing: This minimal config works with QEMU
# For real hardware: Replace with output of 'nixos-generate-config --show-hardware-config'
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Include QEMU guest support for VM testing
    # This adds virtio drivers and other VM-friendly settings
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Boot loader configuration
  # For VM: use systemd-boot (works well with QEMU UEFI)
  # For real hardware: adjust based on your setup (BIOS vs UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Filesystem configuration
  # For VM: nixos-rebuild build-vm creates its own disk, so this is mostly placeholder
  # For real hardware: configure your actual partitions here
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # VM-specific: don't require the disk to exist during build
  # This lets 'nix build' succeed even though the disk doesn't exist yet
  fileSystems."/".options = [ "defaults" ];

  # No swap for VM testing (keeps things simple)
  swapDevices = [ ];

  # Hardware settings
  # For VM: QEMU provides generic x86_64
  # For real hardware: add your specific kernel modules, firmware, etc.
  hardware.enableRedistributableFirmware = true;
}
