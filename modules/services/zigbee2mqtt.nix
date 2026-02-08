# Zigbee2MQTT container module
#
# Runs Zigbee2MQTT via Podman OCI containers and generates
# configuration.yaml from module options at service startup.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.zigbee2mqtt;
in
{
  options.homelab.services.zigbee2mqtt = {
    enable = lib.mkEnableOption "Zigbee2MQTT container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/koenkk/zigbee2mqtt:1.42.0";
      description = "Container image for Zigbee2MQTT.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Host port for Zigbee2MQTT frontend (proxied by Caddy).";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "zigbee.frame1.hobitin.eu";
      description = "Domain for Zigbee2MQTT frontend via Caddy.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/zigbee2mqtt";
      description = "Persistent data directory mounted into the container.";
    };

    serialPort = lib.mkOption {
      type = lib.types.str;
      default = "/dev/serial/by-id/usb-CHANGEME";
      description = "Stable serial device path for Zigbee coordinator.";
    };

    adapter = lib.mkOption {
      type = lib.types.enum [ "auto" "ember" "zstack" "deconz" "ezsp" ];
      default = "ember";
      description = "Zigbee adapter type used by Zigbee2MQTT.";
    };

    mqtt = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "mqtt.frame1.hobitin.eu";
        description = "MQTT broker host.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8883;
        description = "MQTT broker TLS port.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "zigbee2mqtt";
        description = "MQTT username for Zigbee2MQTT.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to MQTT password file (agenix secret).";
      };

      caFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/acme/mqtt.frame1.hobitin.eu/fullchain.pem";
        description = "CA/cert chain file used to verify MQTT TLS connection.";
      };

      baseTopic = lib.mkOption {
        type = lib.types.str;
        default = "zigbee2mqtt";
        description = "Base MQTT topic for Zigbee2MQTT.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mqtt.passwordFile != null;
        message = "homelab.services.zigbee2mqtt.mqtt.passwordFile must be set when Zigbee2MQTT is enabled.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
    ];

    # Keep configuration.yaml managed from Nix options while injecting
    # MQTT password from agenix at runtime.
    systemd.services.zigbee2mqtt-config = {
      description = "Generate Zigbee2MQTT configuration";
      wantedBy = [ "podman-zigbee2mqtt.service" ];
      before = [ "podman-zigbee2mqtt.service" ];
      requires = [ "agenix.service" ];
      after = [ "agenix.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        install -d -m 0750 ${cfg.dataDir}

        {
          echo "homeassistant:"
          echo "  enabled: true"
          echo "frontend:"
          echo "  enabled: true"
          echo "  port: 8080"
          echo "mqtt:"
          echo "  server: mqtts://${cfg.mqtt.host}:${toString cfg.mqtt.port}"
          echo "  user: ${cfg.mqtt.user}"
          echo "  password: |-"
          sed 's/^/    /' ${cfg.mqtt.passwordFile}
          echo "  ca: ${cfg.mqtt.caFile}"
          echo "  base_topic: ${cfg.mqtt.baseTopic}"
          echo "serial:"
          echo "  port: ${cfg.serialPort}"
          echo "  adapter: ${cfg.adapter}"
          echo "advanced:"
          echo "  log_level: info"
        } > ${cfg.dataDir}/configuration.yaml

        chmod 0640 ${cfg.dataDir}/configuration.yaml
      '';
    };

    virtualisation.oci-containers.containers.zigbee2mqtt = {
      image = cfg.image;
      autoStart = true;
      autoRemoveOnStop = false;
      pull = "missing";
      ports = [ "127.0.0.1:${toString cfg.port}:8080" ];
      volumes = [
        "${cfg.dataDir}:/app/data"
        "${cfg.mqtt.caFile}:${cfg.mqtt.caFile}:ro"
      ];
      devices = [ "${cfg.serialPort}:${cfg.serialPort}" ];
      extraOptions = [ "--restart=unless-stopped" ];
    };

    systemd.services.podman-zigbee2mqtt = {
      requires = [ "zigbee2mqtt-config.service" ];
      after = [ "zigbee2mqtt-config.service" "mosquitto.service" ];
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = 5;
      };
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} =
      "reverse_proxy localhost:${toString cfg.port}";

    homelab.homepage.services = [{
      name = "Zigbee2MQTT";
      category = "Smart Home";
      description = "Zigbee bridge and device management";
      href = "https://${cfg.domain}:8443";
      icon = "zigbee2mqtt";
    }];
  };
}
