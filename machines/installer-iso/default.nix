# Minimal NixOS installer ISO with WiFi and SSH pre-configured
#
# Build with: ./scripts/build-installer-iso.sh
# Output: result/iso/nixos-*.iso
#
# Features:
# - Auto-connects to home WiFi
# - SSH server with root login enabled
# - Your SSH keys pre-authorized
# - git and vim included for convenience
{ config, pkgs, lib, modulesPath, ... }:

let
  sshKeys = import ../../lib/ssh-keys.nix;
  wifiPassword = builtins.getEnv "WIFI_PASSWORD";
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Disable NetworkManager (conflicts with wpa_supplicant)
  networking.networkmanager.enable = lib.mkForce false;

  # WiFi via wpa_supplicant - password injected at build time via WIFI_PASSWORD env var
  networking.wireless = {
    enable = true;
    networks."Hobitín" = lib.mkIf (wifiPassword != "") {
      psk = wifiPassword;
    };
  };

  # SSH server with root login
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Authorized SSH keys for root (from lib/ssh-keys.nix)
  users.users.root.openssh.authorizedKeys.keys = builtins.attrValues sshKeys;

  # Extra tools for convenience
  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  # Helpful MOTD
  users.motd = ''
    NixOS Installer ISO - Homelab

    WiFi should auto-connect to "Hobitín"
    Run 'ip a' to check network status

    To install, run nixos-anywhere from your workstation:
      nix run github:nix-community/nixos-anywhere -- --flake .#server root@<this-ip>
  '';
}
