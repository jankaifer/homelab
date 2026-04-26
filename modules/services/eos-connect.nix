{ config, lib, ... }:

let
  cfg = config.homelab.services.eosConnect;
  eosCfg = config.homelab.services.akkudoktorEos;
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}"
    + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
in
{
  options.homelab.services.eosConnect = {
    enable = lib.mkEnableOption "EOS Connect energy orchestration dashboard";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/ohand/eos_connect:latest";
      description = "Container image for EOS Connect.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "Host-local EOS Connect web UI port.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "eos-connect.frame1.hobitin.eu";
      description = "Domain for EOS Connect via Caddy.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/eos-connect";
      description = "Persistent EOS Connect data directory.";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = config.time.timeZone;
      description = "Timezone passed to EOS Connect bootstrap configuration.";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "DEBUG" "INFO" "WARNING" "ERROR" ];
      default = "INFO";
      description = "EOS Connect log level.";
    };

    mqtt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Reserve a dedicated MQTT identity for EOS Connect.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to EOS Connect MQTT password file.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = eosCfg.enable;
        message = "homelab.services.eosConnect requires homelab.services.akkudoktorEos.enable.";
      }
      {
        assertion = cfg.mqtt.enable -> cfg.mqtt.passwordFile != null;
        message = "homelab.services.eosConnect.mqtt.passwordFile must be set when MQTT is enabled.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
    ];

    environment.etc."eos-connect/config.yaml".text = ''
      eos_connect_web_port: ${toString cfg.port}
      time_zone: ${cfg.timeZone}
      log_level: ${lib.toLower cfg.logLevel}
    '';

    virtualisation.oci-containers.containers.eos-connect = {
      image = cfg.image;
      autoStart = true;
      autoRemoveOnStop = false;
      pull = "missing";
      volumes = [
        "${cfg.dataDir}:/app/data"
        "/etc/eos-connect/config.yaml:/app/config.yaml:ro"
      ];
      environment = {
        PYTHONUNBUFFERED = "1";
        EOS_WEB_PORT = toString cfg.port;
        EOS_TIMEZONE = cfg.timeZone;
        EOS_LOG_LEVEL = cfg.logLevel;
      };
      extraOptions = [
        "--network=host"
        "--restart=unless-stopped"
      ];
    };

    systemd.services.podman-eos-connect = {
      after = [
        "podman-akkudoktor-eos.service"
        "evcc.service"
        "podman-homeassistant.service"
        "mosquitto.service"
      ];
      wants = [
        "podman-akkudoktor-eos.service"
        "evcc.service"
        "podman-homeassistant.service"
        "mosquitto.service"
      ];
      restartTriggers = [
        config.environment.etc."eos-connect/config.yaml".source
      ];
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = 5;
      };
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} =
      "reverse_proxy 127.0.0.1:${toString cfg.port}";

    homelab.homepage.services = [{
      name = "EOS Connect";
      category = "Smart Home";
      description = "Advisory energy orchestration dashboard";
      href = homepageHref;
      icon = "mdi-transmission-tower";
    }];
  };
}
