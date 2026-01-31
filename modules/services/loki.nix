# Loki log aggregation module
#
# Loki is a horizontally-scalable, highly-available log aggregation system.
# Designed to be cost effective and easy to operate. Uses labels instead of
# full-text indexing.
#
# Log collection is handled by Alloy (see alloy.nix).
#
# Access: logs.lan.kaifer.dev (via Caddy reverse proxy)
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.loki;
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

    # Register with Caddy reverse proxy
    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy localhost:${toString cfg.port}";
  };
}
