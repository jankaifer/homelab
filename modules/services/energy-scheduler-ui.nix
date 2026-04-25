{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.energySchedulerUi;
  schedulerCfg = config.homelab.services.energyScheduler;
  uiSource = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [
      ../../frontend/energy-ui-charts/src
      ../../src/energy_scheduler/ui_static/app.js
    ];
  };
  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "energy-scheduler-ui";
    version = "0.1.0";
    src = uiSource;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/energy-scheduler-ui/src
      cp -R frontend/energy-ui-charts/src/* $out/share/energy-scheduler-ui/src/
      cp src/energy_scheduler/ui_static/app.js $out/share/energy-scheduler-ui/app.js
      makeWrapper ${pkgs.bun}/bin/bun $out/bin/energy-scheduler-ui \
        --add-flags "$out/share/energy-scheduler-ui/src/server.ts" \
        --set ENERGY_UI_APP_JS "$out/share/energy-scheduler-ui/app.js"
      runHook postInstall
    '';
  };
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}" + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
in
{
  options.homelab.services.energySchedulerUi = {
    enable = lib.mkEnableOption "energy scheduler dashboard UI";

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "Package providing the Bun-based energy-scheduler-ui executable.";
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

    systemd.services.energy-scheduler-ui = {
      description = "Energy scheduler dashboard UI";
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
      };
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy localhost:${toString cfg.port}";

    homelab.homepage.services = [{
      name = "Energy Scheduler";
      category = "Smart Home";
      description = "Read-only energy planner dashboard";
      href = homepageHref;
      icon = "chart-line";
    }];
  };
}
