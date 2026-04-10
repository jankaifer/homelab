{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.energyScheduler;
  jsonFormat = pkgs.formats.json { };
  sourceRoot = lib.fileset.toSource {
    root = ../../.;
    fileset = lib.fileset.unions [
      ../../pyproject.toml
      ../../README.md
      ../../src
    ];
  };
  package = pkgs.python3Packages.buildPythonApplication {
    pname = "energy-scheduler";
    version = "0.1.0";
    pyproject = true;
    src = sourceRoot;
    nativeBuildInputs = [
      pkgs.python3Packages.setuptools
    ];
    propagatedBuildInputs = [
      pkgs.python3Packages.pulp
    ];
    doCheck = false;
  };
  settingsWithRuntime =
    lib.recursiveUpdate cfg.settings {
      runtime = (cfg.settings.runtime or { }) // {
        state_dir = cfg.stateDir;
      };
    };
  configFile = jsonFormat.generate "energy-scheduler.json" settingsWithRuntime;
in
{
  options.homelab.services.energyScheduler = {
    enable = lib.mkEnableOption "local energy scheduling daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "Package providing the energy-scheduler executable.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/energy-scheduler";
      description = "State directory for plans, history, and runtime state.";
    };

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = {
        scheduler = {
          bucket_minutes = 15;
          horizon_buckets = 192;
          loop_interval_seconds = 60;
          churn_penalty_czk_per_kw_change = 0.01;
        };
        forecasts = {
          prices = {
            import_czk_per_kwh = builtins.genList (_: 4.5) 192;
            export_czk_per_kwh = builtins.genList (_: 1.0) 192;
          };
          solar = {
            asset_id = "solar-main";
            export_allowed = true;
            curtailment_allowed = true;
            scenarios = [
              {
                id = "solar-low";
                probability = 0.2;
                generation_kwh = builtins.genList (_: 0.0) 192;
                labels.kind = "low";
              }
              {
                id = "solar-expected";
                probability = 0.6;
                generation_kwh = builtins.genList (_: 0.0) 192;
                labels.kind = "expected";
              }
              {
                id = "solar-high";
                probability = 0.2;
                generation_kwh = builtins.genList (_: 0.0) 192;
                labels.kind = "high";
              }
            ];
          };
        };
        assets = {
          scenario_weights = {
            car-departure = 0.7;
            car-home = 0.3;
          };
          battery = {
            asset_id = "home-battery";
            capacity_kwh = 10.0;
            initial_soc_kwh = 5.0;
            min_soc_kwh = 1.0;
            max_soc_kwh = 10.0;
            max_charge_kw = 4.0;
            max_discharge_kw = 4.0;
            charge_efficiency = 0.95;
            discharge_efficiency = 0.95;
            cycle_cost_czk_per_kwh = 0.15;
            grid_charge_allowed = true;
            export_discharge_allowed = true;
            emergency_floor_kwh = 1.5;
            reserve_target_kwh = builtins.genList (_: 3.0) 192;
            reserve_value_czk_per_kwh = builtins.genList (_: 0.02) 192;
          };
          base_load = {
            fixed_demand_kwh = builtins.genList (_: 0.4) 192;
          };
          demands = [
            {
              asset_id = "tesla-model-3";
              bands = [
                {
                  id = "tesla-required";
                  scenario_ids = [ "car-departure" ];
                  start_index = 0;
                  deadline_index = 32;
                  earliest_start_index = 0;
                  latest_finish_index = 32;
                  target_quantity_kwh = 10.0;
                  max_power_kw = 11.0;
                  marginal_value_czk_per_kwh = 5.0;
                  unmet_penalty_czk_per_kwh = 30.0;
                  required_level = true;
                }
                {
                  id = "tesla-extra";
                  scenario_ids = [ "car-departure" "car-home" ];
                  start_index = 0;
                  deadline_index = 64;
                  earliest_start_index = 0;
                  latest_finish_index = 64;
                  target_quantity_kwh = 8.0;
                  max_power_kw = 11.0;
                  marginal_value_czk_per_kwh = 2.0;
                  unmet_penalty_czk_per_kwh = 0.0;
                  required_level = false;
                }
              ];
            }
          ];
        };
      };
      description = "JSON configuration for the energy scheduler.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.energy-scheduler = {
      isSystemUser = true;
      group = "energy-scheduler";
      home = cfg.stateDir;
      createHome = true;
    };

    users.groups.energy-scheduler = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 energy-scheduler energy-scheduler - -"
      "d ${cfg.stateDir}/history 0750 energy-scheduler energy-scheduler - -"
    ];

    systemd.services.energy-scheduler = {
      description = "Local energy scheduling daemon";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "energy-scheduler";
        Group = "energy-scheduler";
        StateDirectory = "energy-scheduler";
        WorkingDirectory = cfg.stateDir;
        ExecStart = "${cfg.package}/bin/energy-scheduler --config ${configFile}";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.stateDir ];
      };
    };
  };
}
