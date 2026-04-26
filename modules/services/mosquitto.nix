# Mosquitto MQTT broker module
#
# Provides TLS-enabled MQTT for Home Assistant and Zigbee2MQTT.
# Certificates are managed by NixOS ACME (Let's Encrypt DNS challenge).
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.mosquitto;
  evccEnabled = lib.attrByPath [ "homelab" "services" "evcc" "enable" ] false config;
  acmeEnvService = "mosquitto-acme-cloudflare-env-${builtins.replaceStrings [ "." "*" ] [ "-" "wildcard" ] cfg.domain}";
  acmeEnvFile = "/run/${acmeEnvService}.env";
  acmeRenewService = "acme-order-renew-${cfg.domain}";
in
{
  options.homelab.services.mosquitto = {
    enable = lib.mkEnableOption "Mosquitto MQTT broker";

    tlsPort = lib.mkOption {
      type = lib.types.port;
      default = 8883;
      description = "TLS MQTT port.";
    };

    loopbackPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Optional plaintext MQTT listener bound to 127.0.0.1 for host-local
        clients such as Home Assistant.
      '';
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "mqtt.frame1.hobitin.eu";
      description = "Domain used for MQTT TLS certificate.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Email used for ACME account registration.";
    };

    dnsResolver = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional DNS resolver override passed to NixOS ACME/lego.";
    };

    dnsPropagationCheck = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether lego should wait for DNS propagation checks.";
    };

    extraLegoFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional global flags to pass to lego for this certificate.";
    };

    extraLegoRunFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional flags to pass to lego run for this certificate.";
    };

    extraLegoRenewFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional flags to pass to lego renew for this certificate.";
    };

    cloudflareDnsTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Environment file for Cloudflare DNS challenge used by NixOS ACME.
        Must contain variables expected by lego's Cloudflare provider.
      '';
    };

    homeAssistantPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to Home Assistant MQTT user password (agenix secret).";
    };

    zigbee2mqttPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to Zigbee2MQTT MQTT user password (agenix secret).";
    };

    frigatePasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to Frigate MQTT user password (agenix secret).";
    };

    evccPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to evcc MQTT user password (agenix secret).";
    };

    allowLAN = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow MQTT TLS port on LAN interfaces.";
    };

    allowTailscale = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow MQTT TLS port on tailscale0 interface.";
    };

    extraAcl = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional ACL entries for the MQTT listener.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acmeEmail != null;
        message = "homelab.services.mosquitto.acmeEmail must be set when Mosquitto is enabled.";
      }
      {
        assertion = cfg.cloudflareDnsTokenFile != null;
        message = "homelab.services.mosquitto.cloudflareDnsTokenFile must be set when Mosquitto is enabled.";
      }
      {
        assertion = cfg.homeAssistantPasswordFile != null;
        message = "homelab.services.mosquitto.homeAssistantPasswordFile must be set when Mosquitto is enabled.";
      }
      {
        assertion = cfg.zigbee2mqttPasswordFile != null;
        message = "homelab.services.mosquitto.zigbee2mqttPasswordFile must be set when Mosquitto is enabled.";
      }
      {
        assertion = evccEnabled -> cfg.evccPasswordFile != null;
        message = "homelab.services.mosquitto.evccPasswordFile must be set when evcc is enabled.";
      }
    ];

    security.acme = {
      acceptTerms = true;
      defaults.email = lib.mkDefault cfg.acmeEmail;
      certs.${cfg.domain} = {
        dnsProvider = "cloudflare";
        environmentFile = acmeEnvFile;
        dnsResolver = cfg.dnsResolver;
        dnsPropagationCheck = cfg.dnsPropagationCheck;
        extraLegoFlags = cfg.extraLegoFlags;
        extraLegoRunFlags = cfg.extraLegoRunFlags;
        extraLegoRenewFlags = cfg.extraLegoRenewFlags;
        group = "mosquitto";
        reloadServices = [ "mosquitto" ];
      };
    };

    systemd.services.${acmeEnvService} = {
      description = "Prepare Cloudflare credentials for Mosquitto ACME";
      wantedBy = [ "${acmeRenewService}.service" ];
      before = [ "${acmeRenewService}.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        export CLOUDFLARE_API_TOKEN=""
        export CLOUDFLARE_DNS_API_TOKEN=""
        export CLOUDFLARE_ZONE_API_TOKEN=""
        export CLOUDFLARE_EMAIL=""
        export CLOUDFLARE_API_KEY=""

        set -a
        . ${lib.escapeShellArg cfg.cloudflareDnsTokenFile}
        set +a

        dns_token="''${CLOUDFLARE_DNS_API_TOKEN:-''${CLOUDFLARE_API_TOKEN:-}}"

        if [ -z "$dns_token" ] && {
          [ -z "''${CLOUDFLARE_EMAIL:-}" ] || [ -z "''${CLOUDFLARE_API_KEY:-}" ];
        }; then
          echo "Cloudflare credentials file must define CLOUDFLARE_DNS_API_TOKEN, CLOUDFLARE_API_TOKEN, or CLOUDFLARE_EMAIL+CLOUDFLARE_API_KEY." >&2
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

    systemd.services.${acmeRenewService} = {
      requires = [ "${acmeEnvService}.service" ];
      after = [ "${acmeEnvService}.service" ];
    };

    services.mosquitto = {
      enable = true;
      listeners = [
        {
          port = cfg.tlsPort;
          users = {
            homeassistant = {
              passwordFile = cfg.homeAssistantPasswordFile;
              acl = [
                "readwrite homeassistant/#"
                "read evcc/#"
                "read frigate/#"
                "readwrite zigbee2mqtt/#"
              ];
            };
            zigbee2mqtt = {
              passwordFile = cfg.zigbee2mqttPasswordFile;
              acl = [
                "readwrite homeassistant/#"
                "readwrite zigbee2mqtt/#"
              ];
            };
          } // lib.optionalAttrs (cfg.frigatePasswordFile != null) {
            frigate = {
              passwordFile = cfg.frigatePasswordFile;
              acl = [
                "readwrite frigate/#"
              ];
            };
          } // lib.optionalAttrs (cfg.evccPasswordFile != null) {
            evcc = {
              passwordFile = cfg.evccPasswordFile;
              acl = [
                "readwrite evcc/#"
              ];
            };
          };
          acl = cfg.extraAcl;
          settings = {
            allow_anonymous = false;
            certfile = "/var/lib/acme/${cfg.domain}/fullchain.pem";
            keyfile = "/var/lib/acme/${cfg.domain}/key.pem";
            tls_version = "tlsv1.2";
          };
        }
      ] ++ lib.optional (cfg.loopbackPort != null) {
        port = cfg.loopbackPort;
        address = "127.0.0.1";
        users = {
          homeassistant = {
            passwordFile = cfg.homeAssistantPasswordFile;
            acl = [
              "readwrite homeassistant/#"
              "read evcc/#"
              "read frigate/#"
              "readwrite zigbee2mqtt/#"
            ];
          };
        } // lib.optionalAttrs (cfg.frigatePasswordFile != null) {
          frigate = {
            passwordFile = cfg.frigatePasswordFile;
            acl = [
              "readwrite frigate/#"
            ];
          };
        } // lib.optionalAttrs (cfg.evccPasswordFile != null) {
          evcc = {
            passwordFile = cfg.evccPasswordFile;
            acl = [
              "readwrite evcc/#"
            ];
          };
        };
        acl = cfg.extraAcl;
        settings = {
          allow_anonymous = false;
        };
      };
      logType = [ "error" "warning" "notice" "information" ];
    };

    # Keep host-local clients on frame1 using the certificate hostname
    # without depending on external DNS or hairpin routing.
    networking.hosts."127.0.0.1" = [ cfg.domain ];

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.allowLAN [ cfg.tlsPort ];

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf (!cfg.allowLAN && cfg.allowTailscale) [
      cfg.tlsPort
    ];
  };
}
