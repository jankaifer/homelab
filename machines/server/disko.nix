# Disk configuration for server installation
# Used by nixos-anywhere via disko for declarative partitioning
#
# Layout:
#   - GPT partition table
#   - 512MB EFI System Partition (FAT32, mounted at /boot)
#   - Remainder as root partition (ext4, mounted at /)
#
# To use a different disk, override disko.devices.disk.main.device
{ lib, ... }:

{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Default to first NVMe disk - override in machine config if needed
        device = lib.mkDefault "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              name = "ESP";
              size = "512M";
              type = "EF00"; # EFI System Partition
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              name = "root";
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
