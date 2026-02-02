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

  # Filesystem configuration is managed by disko.nix for production installs.
  # For VM testing, the VM build system creates its own disk automatically.

  # No swap (keeps things simple)
  swapDevices = [ ];

  # Hardware settings
  # For VM: QEMU provides generic x86_64
  # For real hardware: add your specific kernel modules, firmware, etc.
  hardware.enableRedistributableFirmware = true;
}
