{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.eosConnect;
  eosCfg = config.homelab.services.akkudoktorEos;
  mqttPasswordFile = if cfg.mqtt.passwordFile == null then "/dev/null" else toString cfg.mqtt.passwordFile;
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

      eos:
        source: eos_server
        server: 127.0.0.1
        port: ${toString eosCfg.apiPort}
        timeout: 180
        time_frame: 3600

      evcc:
        url: http://127.0.0.1:7070

      mqtt:
        enabled: ${if cfg.mqtt.enable then "true" else "false"}
        broker: 127.0.0.1
        port: 1883
        user: eos-connect
        password: ""
        tls: false
        ha_mqtt_auto_discovery: true
        ha_mqtt_auto_discovery_prefix: homeassistant
    '';

    systemd.services.eos-connect-bootstrap-config = {
      description = "Apply declarative EOS Connect configuration";
      before = [ "podman-eos-connect.service" ];
      requiredBy = [ "podman-eos-connect.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      path = [ pkgs.python3 ];
      script = ''
        set -euo pipefail

        install -d -m 0750 ${lib.escapeShellArg cfg.dataDir}

        python3 - ${lib.escapeShellArg "${cfg.dataDir}/eos_connect.db"} ${lib.escapeShellArg mqttPasswordFile} <<'PY'
        import json
        import sqlite3
        import sys
        from datetime import datetime, timezone

        db_path = sys.argv[1]
        password_path = sys.argv[2]

        with open(password_path, "r", encoding="utf-8") as f:
            mqtt_password = f.read().strip()

        settings = {
            "_wizard_completed": True,
            "eos.source": "eos_server",
            "eos.server": "127.0.0.1",
            "eos.port": ${toString eosCfg.apiPort},
            "eos.timeout": 180,
            "eos.time_frame": 3600,
            "evcc.url": "http://127.0.0.1:7070",
            "mqtt.enabled": ${if cfg.mqtt.enable then "True" else "False"},
            "mqtt.broker": "127.0.0.1",
            "mqtt.port": 1883,
            "mqtt.user": "eos-connect",
            "mqtt.password": mqtt_password,
            "mqtt.tls": False,
            "mqtt.ha_mqtt_auto_discovery": True,
            "mqtt.ha_mqtt_auto_discovery_prefix": "homeassistant",
            "inverter.type": "default",
        }

        conn = sqlite3.connect(db_path)
        try:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)")
            conn.execute(
                "CREATE TABLE IF NOT EXISTS settings ("
                "key TEXT PRIMARY KEY, "
                "value TEXT NOT NULL, "
                "updated_at TEXT NOT NULL)"
            )
            if conn.execute("SELECT version FROM schema_version").fetchone() is None:
                conn.execute("INSERT INTO schema_version (version) VALUES (1)")

            now = datetime.now(timezone.utc).isoformat()
            for key, value in settings.items():
                conn.execute(
                    "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET "
                    "value = excluded.value, updated_at = excluded.updated_at",
                    (key, json.dumps(value), now),
                )
            conn.commit()
        finally:
            conn.close()
        PY
      '';
    };

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
        "eos-connect-bootstrap-config.service"
        "podman-akkudoktor-eos.service"
        "evcc.service"
        "podman-homeassistant.service"
        "mosquitto.service"
      ];
      wants = [
        "eos-connect-bootstrap-config.service"
        "podman-akkudoktor-eos.service"
        "evcc.service"
        "podman-homeassistant.service"
        "mosquitto.service"
      ];
      restartTriggers = [
        config.environment.etc."eos-connect/config.yaml".source
        config.systemd.services.eos-connect-bootstrap-config.script
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
