# Loki log aggregation module
#
# Loki is a horizontally-scalable, highly-available log aggregation system.
# Designed to be cost effective and easy to operate. Uses labels instead of
# full-text indexing.
#
# Grafana Alloy ships systemd journal logs to Loki.
#
# Access: logs.lan.kaifer.dev (via Caddy reverse proxy)
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.loki;

  # Alloy configuration file for shipping journal logs to Loki
  alloyConfig = pkgs.writeText "alloy-config.alloy" ''
    // Collect systemd journal logs
    loki.source.journal "journal" {
      forward_to = [loki.write.local.receiver]
      labels = {
        job = "systemd-journal",
        host = "${config.networking.hostName}",
      }
      relabel_rules = loki.relabel.journal.rules
    }

    // Relabel rules for journal logs
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

    // Write logs to Loki
    loki.write "local" {
      endpoint {
        url = "http://127.0.0.1:${toString cfg.port}/loki/api/v1/push"
      }
    }
  '';
in
{
  options.homelab.services.loki = {
    enable = lib.mkEnableOption "Loki log aggregation";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = "Port for Loki HTTP API";
    };

    retentionPeriod = lib.mkOption {
      type = lib.types.str;
      default = "360h"; # 15 days in hours
      description = "How long to retain logs (in hours, e.g., 360h for 15 days)";
    };

    alloy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Grafana Alloy to ship systemd journal logs to Loki";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 12345;
        description = "Port for Alloy HTTP server (metrics/health)";
      };
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "logs.lan.kaifer.dev";
      description = "Domain for Loki web UI (via Caddy)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Loki server
    services.loki = {
      enable = true;
      configuration = {
        server = {
          http_listen_port = cfg.port;
          grpc_listen_port = 9096;
        };

        auth_enabled = false;

        common = {
          instance_addr = "127.0.0.1";
          path_prefix = "/var/lib/loki";
          storage = {
            filesystem = {
              chunks_directory = "/var/lib/loki/chunks";
              rules_directory = "/var/lib/loki/rules";
            };
          };
          replication_factor = 1;
          ring = {
            kvstore = {
              store = "inmemory";
            };
          };
        };

        schema_config = {
          configs = [{
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };

        limits_config = {
          retention_period = cfg.retentionPeriod;
          ingestion_rate_mb = 16;
          ingestion_burst_size_mb = 32;
        };

        compactor = {
          working_directory = "/var/lib/loki/compactor";
          compaction_interval = "10m";
          retention_enabled = true;
          retention_delete_delay = "2h";
          delete_request_store = "filesystem";
        };

        query_range = {
          results_cache = {
            cache = {
              embedded_cache = {
                enabled = true;
                max_size_mb = 100;
              };
            };
          };
        };
      };
    };

    # Grafana Alloy - ships logs to Loki (replaces Promtail)
    services.alloy = lib.mkIf cfg.alloy.enable {
      enable = true;
      extraFlags = [
        "--server.http.listen-addr=0.0.0.0:${toString cfg.alloy.port}"
      ];
      configPath = alloyConfig;
    };

    # Alloy needs access to systemd journal
    systemd.services.alloy = lib.mkIf cfg.alloy.enable {
      serviceConfig.SupplementaryGroups = [ "systemd-journal" ];
      after = [ "loki.service" ];
      wants = [ "loki.service" ];
    };

    # Register Alloy scrape target for monitoring
    homelab.prometheus.scrapeConfigs = lib.mkIf cfg.alloy.enable [{
      job_name = "alloy";
      static_configs = [{
        targets = [ "localhost:${toString cfg.alloy.port}" ];
        labels = {
          instance = config.networking.hostName;
        };
      }];
    }];

    # Register with Caddy reverse proxy
    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy localhost:${toString cfg.port}";

    # Register with Homepage dashboard
    # Note: Loki has no web UI - it's an API service used via Grafana
    # Link to /metrics which shows useful info
    homelab.homepage.services = [{
      name = "Loki";
      category = "Monitoring";
      description = "Log Aggregation (API only)";
      href = "https://${cfg.domain}:8443/metrics";
      icon = "loki";
    }];
  };
}
