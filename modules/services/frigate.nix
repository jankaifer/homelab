# Frigate NVR module
#
# Wraps the upstream NixOS Frigate service with homelab defaults:
# - private access via Caddy
# - recordings kept under /nas/nvr
# - no public exposure by default
{ config, lib, ... }:

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
  defaultSettings = {
    mqtt.enabled = false;
    cameras = cfg.cameras;
    record = {
      enabled = true;
      retain.days = cfg.retainDays;
    };
    snapshots.enabled = true;
  };
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
      default = 14;
      description = "Default recording retention window in days.";
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
      hostname = cfg.domain;
      settings = lib.recursiveUpdate defaultSettings cfg.extraSettings;
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

    systemd.services.frigate = {
      requires = [ "frigate-storage-setup.service" ];
      after = [ "frigate-storage-setup.service" ];
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
