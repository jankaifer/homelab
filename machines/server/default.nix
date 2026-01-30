# Server machine configuration
# This is the main entry point for the server's NixOS config
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware.nix
    # Service modules - import all, enable selectively below
    ../../modules/services/caddy.nix
    ../../modules/services/homepage.nix
    ../../modules/services/victoriametrics.nix
    ../../modules/services/loki.nix
    ../../modules/services/alloy.nix
    ../../modules/services/grafana.nix
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
  # Secrets (agenix)
  # ===================

  age.secrets = {
    cloudflare-api-token = {
      file = ../../secrets/cloudflare-api-token.age;
      # Caddy needs to read this file
      owner = "caddy";
      group = "caddy";
    };
    grafana-admin-password = {
      file = ../../secrets/grafana-admin-password.age;
      owner = "grafana";
      group = "grafana";
    };
  };

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
      apiTokenFile = config.age.secrets.cloudflare-api-token.path;
    };

    virtualHosts = {
      "lan.kaifer.dev" = "reverse_proxy localhost:3000";
    };
  };

  # VictoriaMetrics - metrics collection (Prometheus-compatible, more efficient)
  homelab.services.victoriametrics = {
    enable = true;
    # nodeExporter.enable = true; # Default, collects system metrics
    # retentionPeriod = "15d"; # Default
    # domain = "metrics.lan.kaifer.dev"; # Default
  };

  # Loki - log storage
  homelab.services.loki = {
    enable = true;
    # retentionPeriod = "360h"; # Default, 15 days
    # domain = "logs.lan.kaifer.dev"; # Default
  };

  # Alloy - telemetry collector (logs, metrics, traces)
  homelab.services.alloy = {
    enable = true;
    # logs.enable = true; # Default, ships systemd journal to Loki
  };

  # Grafana - dashboards and visualization
  homelab.services.grafana = {
    enable = true;
    # port = 3001; # Default
    # domain = "grafana.lan.kaifer.dev"; # Default
    adminPassword = null; # Don't use hardcoded password
    adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  };
}
