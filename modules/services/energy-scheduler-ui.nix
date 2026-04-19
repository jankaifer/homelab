{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.energySchedulerUi;
  schedulerCfg = config.homelab.services.energyScheduler;
  package = schedulerCfg.package;
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}" + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
in
{
  options.homelab.services.energySchedulerUi = {
    enable = lib.mkEnableOption "energy scheduler explainability UI";

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "Package providing the energy-scheduler-ui executable.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "Internal port for the UI backend.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "energy.frame1.hobitin.eu";
      description = "Caddy-routed domain for the UI.";
    };

    schedulerStateDir = lib.mkOption {
      type = lib.types.str;
      default = schedulerCfg.stateDir;
      description = "State directory shared with the scheduler.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.energy-scheduler = lib.mkDefault { };

    users.users.energy-scheduler-ui = {
      isSystemUser = true;
      group = "energy-scheduler";
      home = cfg.schedulerStateDir;
      createHome = false;
    };

    systemd.tmpfiles.rules = [
      "f ${cfg.schedulerStateDir}/tesla-calendar.json 0660 energy-scheduler energy-scheduler - -"
      "d ${cfg.schedulerStateDir}/workbench 0770 energy-scheduler energy-scheduler - -"
      "d ${cfg.schedulerStateDir}/workbench/scenarios 0770 energy-scheduler energy-scheduler - -"
      "d ${cfg.schedulerStateDir}/workbench/results 0770 energy-scheduler energy-scheduler - -"
      "d ${cfg.schedulerStateDir}/workbench/runtime 0770 energy-scheduler energy-scheduler - -"
    ];

    systemd.services.energy-scheduler-ui = {
      description = "Energy scheduler explainability UI";
      after = [ "network-online.target" "energy-scheduler.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "energy-scheduler-ui";
        Group = "energy-scheduler";
        ExecStart = "${cfg.package}/bin/energy-scheduler-ui --config ${pkgs.formats.json { }.generate "energy-scheduler-ui.json" (lib.recursiveUpdate schedulerCfg.settings { runtime.state_dir = cfg.schedulerStateDir; })} --port ${toString cfg.port}";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadOnlyPaths = [ cfg.schedulerStateDir ];
        ReadWritePaths = [
          "${cfg.schedulerStateDir}/tesla-calendar.json"
          "${cfg.schedulerStateDir}/workbench"
        ];
      };
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy localhost:${toString cfg.port}";

    homelab.homepage.services = [{
      name = "Energy Scheduler";
      category = "Smart Home";
      description = "Planner explainability UI and Tesla departure calendar";
      href = homepageHref;
      icon = "chart-line";
    }];
  };
}
