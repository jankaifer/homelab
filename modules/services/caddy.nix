# Caddy reverse proxy module
#
# Caddy is a modern web server with automatic HTTPS.
# This module wraps NixOS's caddy service with homelab-specific defaults.
#
# Supports:
# - Self-signed certs for quick local testing (localTls)
# - Let's Encrypt with Cloudflare DNS challenge (cloudflareDns)
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.caddy;

  # Build Caddy with Cloudflare DNS plugin if needed
  caddyPackage =
    if cfg.cloudflareDns.enable then
      pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
        hash = "sha256-dnhEjopeA0UiI+XVYHYpsjcEI6Y1Hacbi28hVKYQURg=";
      }
    else
      pkgs.caddy;
in
{
  options.homelab.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "HTTP port for Caddy";
    };

    httpsPort = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "HTTPS port for Caddy";
    };

    # Self-signed certs for quick local testing (no DNS required)
    localTls = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Caddy's internal TLS (self-signed certs) for local testing";
    };

    # ACME email for Let's Encrypt
    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email for Let's Encrypt ACME registration";
    };

    # Cloudflare DNS challenge for Let's Encrypt
    cloudflareDns = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use Cloudflare DNS challenge for Let's Encrypt certificates";
      };

      apiTokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Runtime path to env file with CLOUDFLARE_API_TOKEN=... (for production with agenix)";
      };

      # For VM testing only - DO NOT use in production!
      apiToken = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Cloudflare API token directly (INSECURE - for VM testing only!)";
      };
    };

    # Virtual hosts configuration
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
    assertions = [
      {
        assertion = cfg.cloudflareDns.enable -> (cfg.cloudflareDns.apiTokenFile != null || cfg.cloudflareDns.apiToken != null);
        message = "homelab.services.caddy.cloudflareDns: either apiTokenFile or apiToken must be set";
      }
      {
        assertion = cfg.cloudflareDns.enable -> cfg.acmeEmail != null;
        message = "homelab.services.caddy.acmeEmail must be set when cloudflareDns is enabled";
      }
    ];

    services.caddy = {
      enable = true;
      package = caddyPackage;

      # Global settings
      globalConfig = lib.mkIf (cfg.acmeEmail != null) ''
        email ${cfg.acmeEmail}
      '';

      # Build the Caddyfile from virtualHosts
      extraConfig = lib.concatStringsSep "\n\n" (
        lib.mapAttrsToList (domain: domainConfig: ''
          ${domain} {
            ${lib.optionalString cfg.localTls "tls internal"}
            ${lib.optionalString cfg.cloudflareDns.enable ''
              tls {
                dns cloudflare {env.CLOUDFLARE_API_TOKEN}
              }
            ''}
            ${domainConfig}
          }
        '') cfg.virtualHosts
      );
    };

    # Pass Cloudflare API token via environment variable
    systemd.services.caddy = lib.mkIf cfg.cloudflareDns.enable {
      serviceConfig = lib.mkIf (cfg.cloudflareDns.apiTokenFile != null) {
        EnvironmentFile = cfg.cloudflareDns.apiTokenFile;
      };
      environment = lib.mkIf (cfg.cloudflareDns.apiToken != null) {
        CLOUDFLARE_API_TOKEN = cfg.cloudflareDns.apiToken;
      };
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort ];
  };
}
