# Frigate NVR module
#
# Wraps the upstream NixOS Frigate service with homelab defaults:
# - private access via Caddy
# - recordings kept under /nas/nvr
# - no public exposure by default
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.frigate;
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}"
    + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
  nasCfg = config.homelab.services.nas;
  recordingsOnNas = lib.hasPrefix "/nas/" cfg.recordingsDir;
  frigateStateDir = "/var/lib/frigate";
  mediaSubdirs = [
    "clips"
    "exports"
    "recordings"
  ];
  mqttSettings =
    lib.optionalAttrs cfg.mqtt.enable ({
      mqtt = {
        enabled = true;
        host = cfg.mqtt.host;
        port = cfg.mqtt.port;
        user = cfg.mqtt.user;
        topic_prefix = cfg.mqtt.topicPrefix;
        client_id = cfg.mqtt.clientId;
        tls_ca_certs = cfg.mqtt.tlsCaFile;
      }
      // lib.optionalAttrs cfg.mqtt.tlsInsecure {
        tls_insecure = true;
      };
    });
  defaultSettings = {
    mqtt.enabled = false;
    cameras = cfg.cameras;
    record = {
      enabled = true;
      retain = {
        days = cfg.continuousRetainDays;
        mode = cfg.retainMode;
      };
      alerts.retain = {
        days = cfg.reviewRetainDays;
        mode = cfg.reviewRetainMode;
      };
      detections.retain = {
        days = cfg.reviewRetainDays;
        mode = cfg.reviewRetainMode;
      };
    };
    snapshots = {
      enabled = cfg.snapshots.enable;
      clean_copy = cfg.snapshots.cleanCopy;
      retain.default = cfg.snapshots.retainDays;
    };
  };
  effectiveSettings = lib.recursiveUpdate (lib.recursiveUpdate defaultSettings mqttSettings) cfg.extraSettings;
  runtimeConfigTemplate = pkgs.writeText "frigate-runtime-config.json" (
    builtins.toJSON (lib.filterAttrsRecursive (_: v: v != null) effectiveSettings)
  );
in
{
  options.homelab.services.frigate = {
    enable = lib.mkEnableOption "Frigate NVR";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "frigate.frame1.hobitin.eu";
      description = "Domain used for Frigate behind Caddy.";
    };

    recordingsDir = lib.mkOption {
      type = lib.types.str;
      default = "/nas/nvr/frigate";
      description = "Directory used for Frigate clips, exports, and recordings.";
    };

    retainDays = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 7;
      description = "Default motion recording retention window in days for newer Frigate versions.";
    };

    continuousRetainDays = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 3;
      description = "How many days of continuous recordings to retain.";
    };

    retainMode = lib.mkOption {
      type = lib.types.enum [ "all" "motion" "active_objects" ];
      default = "all";
      description = "How base recording retention is interpreted by the deployed Frigate version.";
    };

    reviewRetainDays = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 365;
      description = "How many days to retain recordings tied to alerts or detections.";
    };

    reviewRetainMode = lib.mkOption {
      type = lib.types.enum [ "all" "motion" "active_objects" ];
      default = "motion";
      description = "How much video around alerts or detections to keep.";
    };

    cameras = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      example = {
        front_door = {
          ffmpeg.inputs = [{
            path = "rtsp://camera.example.invalid/stream";
            roles = [ "record" ];
          }];
        };
      };
      description = ''
        Frigate camera definitions passed into `services.frigate.settings.cameras`.
        This must be populated before the service can be enabled.
      '';
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Additional Frigate settings merged over the homelab defaults.";
    };

    mqtt = {
      enable = lib.mkEnableOption "Frigate MQTT publishing";

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "MQTT broker hostname for Frigate.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1883;
        description = "MQTT broker port for Frigate.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "frigate";
        description = "MQTT username used by Frigate.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Secret-backed file containing the MQTT password for Frigate.";
      };

      topicPrefix = lib.mkOption {
        type = lib.types.str;
        default = "frigate";
        description = "MQTT topic prefix used by Frigate events and stats.";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "frigate";
        description = "MQTT client ID used by Frigate.";
      };

      tlsCaFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional CA bundle path for TLS MQTT connections.";
      };

      tlsInsecure = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow insecure TLS verification for MQTT. Leave disabled unless testing.";
      };
    };

    snapshots = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether Frigate should save object snapshots.";
      };

      retainDays = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 7;
        description = "How many days to retain snapshots.";
      };

      cleanCopy = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to keep Frigate clean-copy snapshots alongside the regular snapshot.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.services.caddy.enable;
        message = "homelab.services.frigate requires homelab.services.caddy to be enabled.";
      }
      {
        assertion = cfg.cameras != { };
        message = ''
          homelab.services.frigate.cameras is empty.
          Add at least one real RTSP camera definition before enabling Frigate.
        '';
      }
      {
        assertion = (!recordingsOnNas) || nasCfg.enable;
        message = "homelab.services.frigate.recordingsDir uses /nas but homelab.services.nas is not enabled.";
      }
      {
        assertion = (!cfg.mqtt.enable) || (cfg.mqtt.passwordFile != null);
        message = "homelab.services.frigate.mqtt.passwordFile must be set when MQTT is enabled.";
      }
    ];

    users.users.frigate.extraGroups = lib.mkIf recordingsOnNas [ nasCfg.sharedGroup ];

    systemd.services.frigate-storage-setup = {
      description = "Prepare Frigate media storage";
      requiredBy = [ "frigate.service" ];
      before = [ "frigate.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        install -d -m 0750 -o frigate -g frigate ${frigateStateDir}
        install -d -m 2770 -o frigate -g ${if recordingsOnNas then nasCfg.sharedGroup else "frigate"} ${cfg.recordingsDir}

        ${lib.concatMapStringsSep "\n" (name: ''
          install -d -m 2770 -o frigate -g ${if recordingsOnNas then nasCfg.sharedGroup else "frigate"} ${cfg.recordingsDir}/${name}

          if [ -e ${frigateStateDir}/${name} ] && [ ! -L ${frigateStateDir}/${name} ]; then
            echo "${frigateStateDir}/${name} already exists and is not a symlink." >&2
            exit 1
          fi

          ln -sfn ${cfg.recordingsDir}/${name} ${frigateStateDir}/${name}
        '') mediaSubdirs}
      '';
    };

    services.frigate = {
      enable = true;
      checkConfig = false;
      hostname = cfg.domain;
      settings = effectiveSettings;
    };

    # The upstream module injects `listen 127.0.0.1:5000` directly into the
    # Frigate nginx vhost. Give the vhost an explicit loopback-only listener so
    # the nginx module does not fall back to binding :80/:443 on the host
    # alongside Caddy. Caddy continues to proxy to the Frigate-managed listener
    # on 127.0.0.1:5000.
    services.nginx.defaultListen = lib.mkForce [ ];
    services.nginx.virtualHosts.${cfg.domain}.listen = lib.mkForce [{
      addr = "127.0.0.1";
      port = 5003;
    }];
    systemd.services.nginx.serviceConfig.SupplementaryGroups =
      lib.mkIf recordingsOnNas (lib.mkAfter [ nasCfg.sharedGroup ]);

    systemd.services.frigate = {
      requires = [ "frigate-storage-setup.service" ];
      after = [ "frigate-storage-setup.service" ];
      path = lib.mkAfter [ pkgs.jq ];
      preStart = ''
        set -euo pipefail

        ${if cfg.mqtt.enable then ''
          password="$(tr -d '\n' < ${lib.escapeShellArg cfg.mqtt.passwordFile})"
          jq --arg password "$password" '.mqtt.password = $password' \
            ${runtimeConfigTemplate} > /run/frigate/frigate.yml
        '' else ''
          cp --no-preserve=mode ${runtimeConfigTemplate} /run/frigate/frigate.yml
        ''}

        chown frigate:frigate /run/frigate/frigate.yml
        chmod 0600 /run/frigate/frigate.yml
      '';
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} =
      "reverse_proxy 127.0.0.1:5000";

    homelab.homepage.services = [{
      name = "Frigate";
      category = "Smart Home";
      description = "Camera NVR and event review";
      href = homepageHref;
      icon = "frigate";
    }];
  };
}
