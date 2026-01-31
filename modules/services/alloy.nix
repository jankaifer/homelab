# Grafana Alloy telemetry collector module
#
# Alloy is Grafana's OpenTelemetry-compatible collector for logs, metrics, and traces.
# Currently configured to ship systemd journal logs to Loki.
# Future: metrics to VictoriaMetrics, traces to Tempo.
#
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.alloy;
  lokiCfg = config.homelab.services.loki;

  # Alloy configuration file
  alloyConfig = pkgs.writeText "alloy-config.alloy" ''
    // ============================================
    // Logs: systemd journal -> Loki
    // ============================================
    ${lib.optionalString (cfg.logs.enable && lokiCfg.enable) ''
    loki.source.journal "journal" {
      forward_to = [loki.write.local.receiver]
      labels = {
        job = "systemd-journal",
        host = "${config.networking.hostName}",
      }
      relabel_rules = loki.relabel.journal.rules
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "hostname"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
    }

    loki.write "local" {
      endpoint {
        url = "http://127.0.0.1:${toString lokiCfg.port}/loki/api/v1/push"
      }
    }
    ''}

    // ============================================
    // Future: Metrics -> VictoriaMetrics
    // ============================================

    // ============================================
    // Future: Traces -> Tempo
    // ============================================
  '';
in
{
  options.homelab.services.alloy = {
    enable = lib.mkEnableOption "Grafana Alloy telemetry collector";

    port = lib.mkOption {
      type = lib.types.port;
      default = 12345;
      description = "Port for Alloy HTTP server (metrics/health)";
    };

    logs = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Ship systemd journal logs to Loki";
      };
    };

    # Future options:
    # metrics.enable - ship metrics to VictoriaMetrics
    # traces.enable - ship traces to Tempo
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
      extraFlags = [
        "--server.http.listen-addr=0.0.0.0:${toString cfg.port}"
      ];
      configPath = alloyConfig;
    };

    # Alloy needs access to systemd journal for log collection
    systemd.services.alloy = {
      serviceConfig.SupplementaryGroups = lib.mkIf cfg.logs.enable [ "systemd-journal" ];
      # Start after services it depends on
      after = lib.optional lokiCfg.enable "loki.service";
      wants = lib.optional lokiCfg.enable "loki.service";
    };

    # Register Alloy scrape target for monitoring
    homelab.prometheus.scrapeConfigs = [{
      job_name = "alloy";
      static_configs = [{
        targets = [ "localhost:${toString cfg.port}" ];
        labels = {
          instance = config.networking.hostName;
        };
      }];
    }];
  };
}
