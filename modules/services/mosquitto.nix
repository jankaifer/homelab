# Mosquitto MQTT broker module
#
# Provides TLS-enabled MQTT for Home Assistant and Zigbee2MQTT.
# Certificates are managed by NixOS ACME (Let's Encrypt DNS challenge).
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.mosquitto;
in
{
  options.homelab.services.mosquitto = {
    enable = lib.mkEnableOption "Mosquitto MQTT broker";

    tlsPort = lib.mkOption {
      type = lib.types.port;
      default = 8883;
      description = "TLS MQTT port.";
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
    ];

    security.acme = {
      acceptTerms = true;
      defaults.email = lib.mkDefault cfg.acmeEmail;
      certs.${cfg.domain} = {
        dnsProvider = "cloudflare";
        environmentFile = cfg.cloudflareDnsTokenFile;
        group = "mosquitto";
        reloadServices = [ "mosquitto" ];
      };
    };

    services.mosquitto = {
      enable = true;
      listeners = [{
        port = cfg.tlsPort;
        users = {
          homeassistant = {
            passwordFile = cfg.homeAssistantPasswordFile;
            acl = [
              "readwrite homeassistant/#"
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
        };
        acl = cfg.extraAcl;
        settings = {
          allow_anonymous = false;
          certfile = "/var/lib/acme/${cfg.domain}/fullchain.pem";
          keyfile = "/var/lib/acme/${cfg.domain}/key.pem";
          tls_version = "tlsv1.2";
        };
      }];
      logType = [ "error" "warning" "notice" "information" ];
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.allowLAN [ cfg.tlsPort ];

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf (!cfg.allowLAN && cfg.allowTailscale) [
      cfg.tlsPort
    ];
  };
}
