# Grafana dashboards and visualization module
#
# Grafana provides dashboards for metrics (VictoriaMetrics) and logs (Loki).
# Main observability UI for the homelab.
#
# Access: grafana.lan.kaifer.dev (via Caddy reverse proxy)
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.grafana;
  victoriametricsCfg = config.homelab.services.victoriametrics;
  lokiCfg = config.homelab.services.loki;
in
{
  options.homelab.services.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3001; # Grafana default is 3000, but Homepage uses that
      description = "Port for Grafana web UI";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "grafana.lan.kaifer.dev";
      description = "Domain for Grafana web UI (via Caddy)";
    };

    adminPassword = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "admin";
      description = "Admin password (INSECURE - for VM testing only!)";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to file containing admin password (for production with agenix)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;

      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.port;
          domain = cfg.domain;
          root_url = "https://${cfg.domain}";
        };

        security = {
          admin_user = "admin";
          admin_password =
            if cfg.adminPasswordFile != null
            then "$__file{${cfg.adminPasswordFile}}"
            else cfg.adminPassword;
        };

        # Disable analytics
        analytics = {
          reporting_enabled = false;
          check_for_updates = false;
        };
      };

      # Provision data sources declaratively
      provision = {
        enable = true;

        datasources.settings.datasources = [
          # VictoriaMetrics (Prometheus-compatible)
          (lib.mkIf victoriametricsCfg.enable {
            name = "VictoriaMetrics";
            type = "prometheus";
            url = "http://127.0.0.1:${toString victoriametricsCfg.port}";
            isDefault = true;
            editable = false;
          })
          # Loki for logs
          (lib.mkIf lokiCfg.enable {
            name = "Loki";
            type = "loki";
            url = "http://127.0.0.1:${toString lokiCfg.port}";
            editable = false;
          })
        ];
      };
    };

    # Register with Caddy reverse proxy
    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy localhost:${toString cfg.port}";

    # Register with Homepage dashboard
    homelab.homepage.services = [{
      name = "Grafana";
      category = "Monitoring";
      description = "Dashboards & Visualization";
      href = "https://${cfg.domain}:8443";
      icon = "grafana";
    }];
  };
}
