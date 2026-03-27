# Caddy reverse proxy module
#
# Caddy is a modern web server with automatic HTTPS.
# This module wraps NixOS's caddy service with homelab-specific defaults.
#
# Supports:
# - Self-signed certs for quick local testing (localTls)
# - Let's Encrypt via NixOS security.acme with Cloudflare DNS challenge
# - Metrics endpoint for Prometheus scraping
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.caddy;
  domains = builtins.attrNames cfg.virtualHosts;
  acmeEnvService = "caddy-acme-cloudflare-env";
  acmeEnvFile = "/run/${acmeEnvService}.env";
  acmeRenewServices = map (domain: "acme-order-renew-${domain}.service") domains;
  acmeCerts = lib.genAttrs domains (_: {
    dnsProvider = "cloudflare";
    environmentFile = acmeEnvFile;
    group = "caddy";
    reloadServices = [ "caddy" ];
  });
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

    # Cloudflare DNS challenge for Let's Encrypt via security.acme
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

    # Metrics for Prometheus
    metrics = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Caddy metrics endpoint for Prometheus scraping";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 2019;
        description = "Port for Caddy admin/metrics API";
      };
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
      package = pkgs.caddy;

      # Global settings
      globalConfig = lib.concatStringsSep "\n" (lib.filter (x: x != "") [
        (lib.optionalString (cfg.acmeEmail != null) "email ${cfg.acmeEmail}")
        (lib.optionalString cfg.metrics.enable "servers { metrics }")
      ]);

      # Build the Caddyfile from virtualHosts
      extraConfig = lib.concatStringsSep "\n\n" (
        lib.mapAttrsToList
          (domain: domainConfig: ''
            ${domain} {
              ${lib.optionalString cfg.localTls "tls internal"}
              ${lib.optionalString (!cfg.localTls && cfg.cloudflareDns.enable) ''
                tls /var/lib/acme/${domain}/fullchain.pem /var/lib/acme/${domain}/key.pem
              ''}
              ${domainConfig}
            }
          '')
          cfg.virtualHosts
      );
    };

    security.acme = lib.mkIf (!cfg.localTls && cfg.cloudflareDns.enable) {
      acceptTerms = true;
      defaults.email = lib.mkDefault cfg.acmeEmail;
      certs = acmeCerts;
    };

    systemd.services = lib.mkMerge [
      (lib.mkIf (!cfg.localTls && cfg.cloudflareDns.enable) {
        ${acmeEnvService} = {
          description = "Prepare Cloudflare credentials for Caddy ACME";
          wantedBy = acmeRenewServices;
          before = acmeRenewServices;
          serviceConfig = {
            Type = "oneshot";
          };
          script = ''
            set -euo pipefail

            export CLOUDFLARE_API_TOKEN="${lib.optionalString (cfg.cloudflareDns.apiToken != null) cfg.cloudflareDns.apiToken}"
            export CLOUDFLARE_DNS_API_TOKEN=""
            export CLOUDFLARE_ZONE_API_TOKEN=""
            export CLOUDFLARE_EMAIL=""
            export CLOUDFLARE_API_KEY=""

            ${lib.optionalString (cfg.cloudflareDns.apiTokenFile != null) ''
              set -a
              . ${lib.escapeShellArg cfg.cloudflareDns.apiTokenFile}
              set +a
            ''}

            dns_token="''${CLOUDFLARE_DNS_API_TOKEN:-''${CLOUDFLARE_API_TOKEN:-}}"

            if [ -z "$dns_token" ] && {
              [ -z "''${CLOUDFLARE_EMAIL:-}" ] || [ -z "''${CLOUDFLARE_API_KEY:-}" ];
            }; then
              echo "Cloudflare credentials must define CLOUDFLARE_DNS_API_TOKEN, CLOUDFLARE_API_TOKEN, or CLOUDFLARE_EMAIL+CLOUDFLARE_API_KEY." >&2
              exit 1
            fi

            umask 0077
            cat > ${acmeEnvFile} <<EOF
            ''${dns_token:+CLOUDFLARE_DNS_API_TOKEN=$dns_token}
            ''${CLOUDFLARE_ZONE_API_TOKEN:+CLOUDFLARE_ZONE_API_TOKEN=$CLOUDFLARE_ZONE_API_TOKEN}
            ''${CLOUDFLARE_EMAIL:+CLOUDFLARE_EMAIL=$CLOUDFLARE_EMAIL}
            ''${CLOUDFLARE_API_KEY:+CLOUDFLARE_API_KEY=$CLOUDFLARE_API_KEY}
            EOF
          '';
        };
      })
      (lib.mkIf (!cfg.localTls && cfg.cloudflareDns.enable) (
        lib.genAttrs acmeRenewServices (_: {
          requires = [ "${acmeEnvService}.service" ];
          after = [ "${acmeEnvService}.service" ];
        })
      ))
    ];

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [ cfg.httpPort cfg.httpsPort ];

    # Register Caddy metrics with Prometheus (if metrics enabled)
    homelab.prometheus.scrapeConfigs = lib.mkIf cfg.metrics.enable [
      {
        job_name = "caddy";
        static_configs = [{
          targets = [ "localhost:${toString cfg.metrics.port}" ];
          labels = {
            instance = config.networking.hostName;
          };
        }];
      }
    ];
  };
}
