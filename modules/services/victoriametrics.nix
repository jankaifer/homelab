# VictoriaMetrics metrics collection module
#
# VictoriaMetrics is a fast, cost-effective time-series database.
# Drop-in replacement for Prometheus with better resource efficiency.
# Services can register their scrape targets via homelab.prometheus.scrapeConfigs.
#
# Access: metrics.local.kaifer.dev (via Caddy reverse proxy)
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.victoriametrics;
  prometheusCfg = config.homelab.prometheus;

  # Generate prometheus-compatible scrape config file
  scrapeConfigFile = pkgs.writeText "prometheus-scrape.yml" (builtins.toJSON {
    scrape_configs = prometheusCfg.scrapeConfigs;
  });
in
{
  options.homelab.services.victoriametrics = {
    enable = lib.mkEnableOption "VictoriaMetrics metrics collection";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8428;
      description = "Port for VictoriaMetrics web UI and API";
    };

    retentionPeriod = lib.mkOption {
      type = lib.types.str;
      default = "15d";
      description = "How long to retain metrics data (e.g., 15d, 1w, 1y)";
    };

    nodeExporter.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable node_exporter for system metrics";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "metrics.local.kaifer.dev";
      description = "Domain for VictoriaMetrics web UI (via Caddy)";
    };
  };

  # Shared option for services to register their scrape targets (Prometheus-compatible)
  options.homelab.prometheus.scrapeConfigs = lib.mkOption {
    type = lib.types.listOf lib.types.attrs;
    default = [ ];
    description = ''
      List of Prometheus-compatible scrape configurations.
      Services should add their own scrape configs to this list.
      VictoriaMetrics uses the same format as Prometheus.
    '';
    example = [
      {
        job_name = "my-service";
        static_configs = [{ targets = [ "localhost:9100" ]; }];
      }
    ];
  };

  config = lib.mkIf cfg.enable {
    # Enable node_exporter for system metrics (same exporter works with VictoriaMetrics)
    services.prometheus.exporters.node = lib.mkIf cfg.nodeExporter.enable {
      enable = true;
      port = 9100;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };

    # Register node_exporter scrape config
    homelab.prometheus.scrapeConfigs = lib.mkIf cfg.nodeExporter.enable [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "localhost:9100" ];
          labels = {
            instance = config.networking.hostName;
          };
        }];
      }
    ];

    # VictoriaMetrics server
    services.victoriametrics = {
      enable = true;
      listenAddress = "127.0.0.1:${toString cfg.port}";
      retentionPeriod = cfg.retentionPeriod;
      extraOptions = [
        "-promscrape.config=${scrapeConfigFile}"
      ];
    };

    # Register with Caddy reverse proxy
    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy localhost:${toString cfg.port}";

    # Register with Homepage dashboard
    homelab.homepage.services = [{
      name = "VictoriaMetrics";
      category = "Monitoring";
      description = "Metrics Collection";
      href = "https://${cfg.domain}:8443";
      icon = "victoriametrics";
    }];
  };
}
