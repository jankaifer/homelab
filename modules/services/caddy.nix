# Caddy reverse proxy module
#
# Caddy is a modern web server with automatic HTTPS.
# This module wraps NixOS's caddy service with homelab-specific defaults.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.caddy;
in
{
  options.homelab.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    # Port for HTTP traffic (will redirect to HTTPS in production)
    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "HTTP port for Caddy";
    };

    # Port for HTTPS traffic
    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "HTTPS port for Caddy";
    };

    # Virtual hosts configuration
    # Each key is a domain, value is the Caddy config for that domain
    virtualHosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "example.com" = "reverse_proxy localhost:8080";
      };
      description = "Caddy virtual host configurations";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      # Build the Caddyfile from virtualHosts
      # Each entry becomes a server block
      extraConfig = lib.concatStringsSep "\n\n" (
        lib.mapAttrsToList (domain: config: ''
          ${domain} {
            ${config}
          }
        '') cfg.virtualHosts
      );
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort ];
  };
}
