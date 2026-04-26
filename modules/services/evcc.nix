{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.evcc;
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}"
    + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
  mqttEnvDir = "/run/evcc-secrets";
  mqttEnvFile = "${mqttEnvDir}/mqtt.env";
  defaultSettings = {
    log = cfg.logLevel;
    interval = cfg.interval;

    network = {
      schema = "http";
      host = cfg.listenAddress;
      port = cfg.port;
      externalUrl = "https://${cfg.domain}";
    };

    site = {
      title = cfg.siteTitle;
    };
  } // lib.optionalAttrs cfg.mqtt.enable {
    mqtt = {
      broker = "${cfg.mqtt.host}:${toString cfg.mqtt.port}";
      topic = cfg.mqtt.topic;
      user = cfg.mqtt.username;
      password = "$EVCC_MQTT_PASSWORD";
    };
  };
in
{
  options.homelab.services.evcc = {
    enable = lib.mkEnableOption "evcc EV charging and loadpoint service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 7070;
      description = "Internal port for the evcc UI and API.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host value advertised by evcc for local access.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "evcc.frame1.hobitin.eu";
      description = "Caddy-routed domain for evcc.";
    };

    siteTitle = lib.mkOption {
      type = lib.types.str;
      default = "Frame1";
      description = "evcc site title displayed in the UI.";
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "info";
      description = "evcc log level.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "evcc control loop interval.";
    };

    demoMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run evcc with simulated demo devices for first-rollout commissioning.";
    };

    restrictNetworkToLoopback = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Restrict evcc network access to loopback using systemd IP address filtering.";
    };

    allowedNetworkCIDRs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.2.31/32" ];
      description = "Additional network CIDRs evcc may access when loopback restriction is enabled.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional evcc YAML settings merged over the commissioning defaults.";
    };

    mqtt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Publish evcc state to MQTT.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "MQTT broker host used by evcc.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1883;
        description = "MQTT broker port used by evcc.";
      };

      topic = lib.mkOption {
        type = lib.types.str;
        default = "evcc";
        description = "MQTT topic prefix used by evcc.";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "evcc";
        description = "MQTT username used by evcc.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the raw evcc MQTT password file.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mqtt.enable -> cfg.mqtt.passwordFile != null;
        message = "homelab.services.evcc.mqtt.passwordFile must be set when MQTT is enabled.";
      }
    ];

    services.evcc = {
      enable = true;
      environmentFile = lib.mkIf cfg.mqtt.enable mqttEnvFile;
      extraArgs = lib.optional cfg.demoMode "--demo";
      settings = lib.recursiveUpdate defaultSettings cfg.settings;
    };

    systemd.services.evcc-mqtt-env = lib.mkIf cfg.mqtt.enable {
      description = "Prepare evcc MQTT environment";
      before = [ "evcc.service" ];
      requiredBy = [ "evcc.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        install -d -m 0700 ${mqttEnvDir}
        password="$(tr -d '\n' < ${lib.escapeShellArg cfg.mqtt.passwordFile})"
        escaped="$(printf '%s' "$password" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g')"

        umask 0077
        printf 'EVCC_MQTT_PASSWORD="%s"\n' "$escaped" > ${mqttEnvFile}
      '';
    };

    systemd.services.evcc = {
      after = lib.mkIf cfg.mqtt.enable [ "mosquitto.service" "evcc-mqtt-env.service" ];
      requires = lib.mkIf cfg.mqtt.enable [ "evcc-mqtt-env.service" ];
      restartTriggers = lib.optionals cfg.mqtt.enable [
        cfg.mqtt.passwordFile
        config.systemd.services.evcc-mqtt-env.script
      ];
      serviceConfig = lib.mkIf cfg.restrictNetworkToLoopback {
        IPAddressAllow = [ "localhost" ] ++ cfg.allowedNetworkCIDRs;
        IPAddressDeny = [ "any" ];
      };
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} =
      "reverse_proxy 127.0.0.1:${toString cfg.port}";

    homelab.homepage.services = [{
      name = "evcc";
      category = "Smart Home";
      description = "EV charging commissioning";
      href = homepageHref;
      icon = "evcc";
    }];
  };
}
