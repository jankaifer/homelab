# frame1 machine configuration
# This is the main entry point for frame1's NixOS config
{ config, pkgs, lib, ... }:

let
  sshKeys = import ../../lib/ssh-keys.nix;
  allUserKeys = builtins.attrValues sshKeys;
in
{
  imports = [
    ./hardware.nix
    ./disko.nix
    # Service modules - import all, enable selectively below
    ../../modules/services/caddy.nix
    ../../modules/services/homepage.nix
    ../../modules/services/victoriametrics.nix
    ../../modules/services/loki.nix
    ../../modules/services/alloy.nix
    ../../modules/services/grafana.nix
    ../../modules/services/tailscale.nix
  ];

  # Basic system settings
  system.stateVersion = "24.05";
  networking.hostName = "frame1";

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
      PermitRootLogin = "no"; # Disable direct root SSH login
      PasswordAuthentication = false; # Enforce SSH key-only auth
    };
  };

  # Firewall - open SSH port
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # Root user
  users.users.root = {
    initialPassword = "nixos"; # Fallback password
    openssh.authorizedKeys.keys = allUserKeys;
  };

  # Main operator account
  users.users.jankaifer = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "nixos"; # Fallback password
    openssh.authorizedKeys.keys = allUserKeys;
  };

  # Legacy admin user kept temporarily for transition
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "nixos"; # Fallback password
    openssh.authorizedKeys.keys = allUserKeys;
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
  # Secrets are age-encrypted and decrypted at boot time.
  # VM: Uses host's SSH key mounted via virtfs (see vm.nix)
  # Production: Uses server's SSH host key (add to secrets.nix first)

  age.secrets = {
    cloudflare-api-token = {
      file = ../../secrets/cloudflare-api-token.age;
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
    allowedHosts = [ "local.kaifer.dev" "local.kaifer.dev:8443" ];
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
      "local.kaifer.dev" = "reverse_proxy localhost:3000";
    };
  };

  # VictoriaMetrics - metrics collection (Prometheus-compatible, more efficient)
  homelab.services.victoriametrics = {
    enable = true;
    # nodeExporter.enable = true; # Default, collects system metrics
    # retentionPeriod = "15d"; # Default
    # domain = "metrics.local.kaifer.dev"; # Default
  };

  # Loki - log storage
  homelab.services.loki = {
    enable = true;
    # retentionPeriod = "360h"; # Default, 15 days
    # domain = "logs.local.kaifer.dev"; # Default
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
    # domain = "grafana.local.kaifer.dev"; # Default
    adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  };

  # Tailscale - VPN for remote access
  homelab.services.tailscale = {
    enable = true;
    # acceptRoutes = false; # Default
    # exitNode = false; # Default
  };
}
