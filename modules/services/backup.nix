# Restic backup orchestration for homelab Tier-1 data
{ config, lib, ... }:

let
  cfg = config.homelab.services.backup;
  retainYearly = 100; # Operationally "indefinite" for the homelab horizon.
in
{
  options.homelab.services.backup = {
    enable = lib.mkEnableOption "restic backups for Tier-1 homelab state";

    repositoryEnvFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Environment file containing RESTIC_REPOSITORY and any object-store
        credentials required by restic.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the restic repository password file.";
    };

    timer = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "OnCalendar expression for the scheduled backup timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repositoryEnvFile != null;
        message = "homelab.services.backup.repositoryEnvFile must be set when backups are enabled.";
      }
      {
        assertion = cfg.passwordFile != null;
        message = "homelab.services.backup.passwordFile must be set when backups are enabled.";
      }
    ];

    services.restic.backups.frame1 = {
      initialize = true;
      passwordFile = cfg.passwordFile;
      environmentFile = cfg.repositoryEnvFile;
      timerConfig = {
        OnCalendar = cfg.timer;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      paths = [
        "/var/lib/homeassistant"
        "/var/lib/zigbee2mqtt"
        "/var/lib/victoriametrics"
        "/var/lib/grafana"
        "/var/lib/tailscale"
        "/etc/ssh"
        "/nas/private"
      ];
      pruneOpts = [
        "--keep-daily 30"
        "--keep-monthly 12"
        "--keep-yearly ${toString retainYearly}"
      ];
      checkOpts = [
        "--read-data-subset=1/20"
      ];
      extraBackupArgs = [
        "--one-file-system"
        "--tag homelab"
        "--tag frame1"
        "--tag tier1"
      ];
      backupPrepareCommand = ''
        set -euo pipefail
        systemctl stop podman-homeassistant.service
      '';
      backupCleanupCommand = ''
        set -euo pipefail
        systemctl start podman-homeassistant.service
      '';
    };
  };
}
