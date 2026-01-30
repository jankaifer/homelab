# Server machine configuration
# This is the main entry point for the server's NixOS config
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    # Service modules - import all, enable selectively below
    ../../modules/services/caddy.nix
    ../../modules/services/homepage.nix
  ];

  # Basic system settings
  system.stateVersion = "24.05";
  networking.hostName = "server";

  # Enable flakes (required since we're using a flake-based config)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow unfree packages if needed (for things like nvidia drivers, etc)
  nixpkgs.config.allowUnfree = true;

  # Timezone - adjust to your location
  time.timeZone = "Europe/Prague";

  # Basic networking
  networking.networkmanager.enable = true;

  # SSH server - essential for remote management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # For VM testing; tighten for production
      PasswordAuthentication = true; # For VM testing; use keys in production
    };
  };

  # Firewall - open SSH port
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # Root user - empty password for VM testing
  # WARNING: Change this for production! Use agenix for real passwords/keys
  users.users.root = {
    initialPassword = "nixos"; # Simple password for VM testing
  };

  # Create a regular user for daily use
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "nixos"; # Simple password for VM testing
  };

  # Allow wheel group to sudo without password (convenient for testing)
  security.sudo.wheelNeedsPassword = false;

  # Essential packages available system-wide
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
  ];

  # ===================
  # Services
  # ===================

  # Homepage dashboard - only accessible through Caddy reverse proxy
  homelab.services.homepage = {
    enable = true;
    port = 3000;
    openFirewall = false; # Access through Caddy only
    allowedHosts = [ "lan.kaifer.dev" "lan.kaifer.dev:8443" ];
  };

  # Caddy reverse proxy - entry point for all web services
  homelab.services.caddy = {
    enable = true;
    acmeEmail = "jan@kaifer.cz"; # For Let's Encrypt registration

    # Use Cloudflare DNS challenge for real certificates
    cloudflareDns = {
      enable = true;
      # For VM testing: set apiToken directly (will prompt for value)
      # For production: use apiTokenFile with agenix secret
      apiToken = "ai7v1yyM-RN0nVJ96vJfEy8NHk7HJlmWv70W1N62";
    };

    virtualHosts = {
      "lan.kaifer.dev" = "reverse_proxy localhost:3000";
    };
  };
}
