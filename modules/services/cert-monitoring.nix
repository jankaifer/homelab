# Certificate expiry and renewal visibility via node_exporter textfile metrics
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.certMonitoring;
  caddyCfg = config.homelab.services.caddy;
  mosquittoCfg = config.homelab.services.mosquitto;
  metricsDatasource = "VictoriaMetrics";
  caddyDomains = lib.attrNames caddyCfg.virtualHosts;
  renewalUnits =
    (lib.map
      (domain: {
        inherit domain;
        certPath = "/var/lib/acme/${domain}/fullchain.pem";
        unit = "acme-order-renew-${domain}.service";
        kind = "caddy";
      })
      caddyDomains)
    ++ lib.optional mosquittoCfg.enable {
      domain = mosquittoCfg.domain;
      certPath = "/var/lib/acme/${mosquittoCfg.domain}/fullchain.pem";
      unit = "acme-order-renew-${mosquittoCfg.domain}.service";
      kind = "mosquitto";
    };
  certMetricsScript = pkgs.writeShellScript "homelab-cert-metrics" ''
    set -euo pipefail

    out="${cfg.textfileDir}/homelab-certificates.prom"
    tmp="$(mktemp)"
    now="$(${pkgs.coreutils}/bin/date +%s)"

    {
      echo "# HELP homelab_certificate_present Whether the certificate file exists."
      echo "# TYPE homelab_certificate_present gauge"
      echo "# HELP homelab_certificate_days_until_expiry Whole days until certificate expiry."
      echo "# TYPE homelab_certificate_days_until_expiry gauge"
      echo "# HELP homelab_certificate_expiring_soon Whether the certificate is inside the warning horizon."
      echo "# TYPE homelab_certificate_expiring_soon gauge"
      echo "# HELP homelab_certificate_renewal_unit_result Whether the last renewal unit run succeeded."
      echo "# TYPE homelab_certificate_renewal_unit_result gauge"
      echo "# HELP homelab_certificate_renewal_unit_last_exit_timestamp_seconds Unix timestamp of the last observed renewal-unit exit."
      echo "# TYPE homelab_certificate_renewal_unit_last_exit_timestamp_seconds gauge"

      ${lib.concatMapStringsSep "\n" (entry: ''
        if [ -f "${entry.certPath}" ]; then
          not_after_raw="$(${pkgs.openssl}/bin/openssl x509 -enddate -noout -in "${entry.certPath}" | ${pkgs.coreutils}/bin/cut -d= -f2-)"
          not_after="$(${pkgs.coreutils}/bin/date -d "$not_after_raw" +%s)"
          days_left="$(( (not_after - now) / 86400 ))"
          soon=0
          if [ "$days_left" -le ${toString cfg.warningDays} ]; then
            soon=1
          fi
          echo "homelab_certificate_present{domain=\"${entry.domain}\",kind=\"${entry.kind}\"} 1"
          echo "homelab_certificate_days_until_expiry{domain=\"${entry.domain}\",kind=\"${entry.kind}\"} $days_left"
          echo "homelab_certificate_expiring_soon{domain=\"${entry.domain}\",kind=\"${entry.kind}\"} $soon"
        else
          echo "homelab_certificate_present{domain=\"${entry.domain}\",kind=\"${entry.kind}\"} 0"
          echo "homelab_certificate_days_until_expiry{domain=\"${entry.domain}\",kind=\"${entry.kind}\"} -1"
          echo "homelab_certificate_expiring_soon{domain=\"${entry.domain}\",kind=\"${entry.kind}\"} 1"
        fi

        if ${pkgs.systemd}/bin/systemctl list-unit-files "${entry.unit}" --no-legend >/dev/null 2>&1; then
          result="$(${pkgs.systemd}/bin/systemctl show "${entry.unit}" --property=Result --value)"
          exit_ts="$(${pkgs.systemd}/bin/systemctl show "${entry.unit}" --property=ExecMainExitTimestamp --value)"
          success=0
          if [ "$result" = "success" ]; then
            success=1
          fi
          if [ -n "$exit_ts" ]; then
            exit_epoch="$(${pkgs.coreutils}/bin/date -d "$exit_ts" +%s 2>/dev/null || echo 0)"
          else
            exit_epoch=0
          fi
          echo "homelab_certificate_renewal_unit_result{domain=\"${entry.domain}\",kind=\"${entry.kind}\",unit=\"${entry.unit}\"} $success"
          echo "homelab_certificate_renewal_unit_last_exit_timestamp_seconds{domain=\"${entry.domain}\",kind=\"${entry.kind}\",unit=\"${entry.unit}\"} $exit_epoch"
        else
          echo "homelab_certificate_renewal_unit_result{domain=\"${entry.domain}\",kind=\"${entry.kind}\",unit=\"${entry.unit}\"} 0"
          echo "homelab_certificate_renewal_unit_last_exit_timestamp_seconds{domain=\"${entry.domain}\",kind=\"${entry.kind}\",unit=\"${entry.unit}\"} 0"
        fi
      '') renewalUnits}
    } > "$tmp"

    ${pkgs.coreutils}/bin/install -m 0644 "$tmp" "$out"
    ${pkgs.coreutils}/bin/rm -f "$tmp"
  '';
  dashboardJson = pkgs.writeText "homelab-certificates-dashboard.json" (builtins.toJSON {
    annotations = { list = [ ]; };
    editable = true;
    graphTooltip = 0;
    links = [ ];
    panels = [
      {
        datasource = metricsDatasource;
        fieldConfig = {
          defaults = {
            color = {
              mode = "thresholds";
            };
            decimals = 0;
            mappings = [ ];
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "red";
                  value = null;
                }
                {
                  color = "orange";
                  value = cfg.warningDays;
                }
                {
                  color = "green";
                  value = 30;
                }
              ];
            };
            unit = "d";
          };
          overrides = [ ];
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 0;
          y = 0;
        };
        id = 1;
        options = {
          colorMode = "value";
          graphMode = "none";
          justifyMode = "auto";
          orientation = "auto";
          reduceOptions = {
            calcs = [ "min" ];
            fields = "";
            values = false;
          };
          textMode = "auto";
        };
        pluginVersion = "11.5.2";
        targets = [
          {
            datasource = metricsDatasource;
            expr = "min(homelab_certificate_days_until_expiry)";
            instant = true;
            legendFormat = "closest expiry";
            refId = "A";
          }
        ];
        title = "Closest Certificate Expiry";
        type = "stat";
      }
      {
        datasource = metricsDatasource;
        fieldConfig = {
          defaults = {
            color = {
              mode = "thresholds";
            };
            mappings = [
              {
                options = {
                  "0" = {
                    color = "green";
                    text = "Healthy";
                  };
                  "1" = {
                    color = "red";
                    text = "Warning";
                  };
                };
                type = "value";
              }
            ];
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "green";
                  value = null;
                }
                {
                  color = "red";
                  value = 1;
                }
              ];
            };
          };
          overrides = [ ];
        };
        gridPos = {
          h = 8;
          w = 12;
          x = 12;
          y = 0;
        };
        id = 2;
        options = {
          colorMode = "value";
          graphMode = "none";
          justifyMode = "auto";
          orientation = "auto";
          reduceOptions = {
            calcs = [ "max" ];
            fields = "";
            values = false;
          };
          textMode = "auto";
        };
        pluginVersion = "11.5.2";
        targets = [
          {
            datasource = metricsDatasource;
            expr = "max(homelab_certificate_expiring_soon)";
            instant = true;
            legendFormat = "expiring soon";
            refId = "A";
          }
        ];
        title = "Any Certificate Inside 14 Days";
        type = "stat";
      }
      {
        datasource = metricsDatasource;
        fieldConfig = {
          defaults = {
            custom = {
              align = "auto";
              displayMode = "auto";
            };
            mappings = [ ];
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "green";
                  value = null;
                }
              ];
            };
          };
          overrides = [ ];
        };
        gridPos = {
          h = 10;
          w = 12;
          x = 0;
          y = 8;
        };
        id = 3;
        options = {
          cellHeight = "sm";
          footer = {
            fields = "";
            reducer = [ "sum" ];
            show = false;
          };
          showHeader = true;
          sortBy = [
            {
              desc = true;
              displayName = "days_left";
            }
          ];
        };
        pluginVersion = "11.5.2";
        targets = [
          {
            datasource = metricsDatasource;
            expr = "homelab_certificate_days_until_expiry";
            format = "table";
            instant = true;
            legendFormat = "__auto";
            refId = "A";
          }
        ];
        title = "Certificate Expiry by Domain";
        transformations = [
          {
            id = "organize";
            options = {
              excludeByName = { Time = true; };
              indexByName = {
                Value = 2;
                domain = 0;
                kind = 1;
              };
              renameByName = {
                Value = "days_left";
              };
            };
          }
        ];
        type = "table";
      }
      {
        datasource = metricsDatasource;
        fieldConfig = {
          defaults = {
            custom = {
              align = "auto";
              displayMode = "color-background";
            };
            mappings = [
              {
                options = {
                  "0" = {
                    color = "red";
                    text = "Not OK";
                  };
                  "1" = {
                    color = "green";
                    text = "OK";
                  };
                };
                type = "value";
              }
            ];
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "red";
                  value = null;
                }
                {
                  color = "green";
                  value = 1;
                }
              ];
            };
          };
          overrides = [ ];
        };
        gridPos = {
          h = 10;
          w = 12;
          x = 12;
          y = 8;
        };
        id = 4;
        options = {
          cellHeight = "sm";
          footer = {
            fields = "";
            reducer = [ "sum" ];
            show = false;
          };
          showHeader = true;
        };
        pluginVersion = "11.5.2";
        targets = [
          {
            datasource = metricsDatasource;
            expr = "homelab_certificate_renewal_unit_result";
            format = "table";
            instant = true;
            legendFormat = "__auto";
            refId = "A";
          }
        ];
        title = "Renewal Unit Status";
        transformations = [
          {
            id = "organize";
            options = {
              excludeByName = { Time = true; };
              indexByName = {
                Value = 3;
                domain = 0;
                kind = 1;
                unit = 2;
              };
              renameByName = {
                Value = "last_result_ok";
              };
            };
          }
        ];
        type = "table";
      }
    ];
    refresh = "15m";
    schemaVersion = 39;
    style = "dark";
    tags = [ "homelab" "certificates" ];
    templating = {
      list = [ ];
    };
    time = {
      from = "now-30d";
      to = "now";
    };
    timezone = "browser";
    title = "Certificate Health";
    uid = "homelab-certificates";
    version = 1;
  });
in
{
  options.homelab.services.certMonitoring = {
    enable = lib.mkEnableOption "certificate health metrics";

    warningDays = lib.mkOption {
      type = lib.types.int;
      default = 14;
      description = "How many days before expiry a certificate is considered warning-level.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15m";
      description = "How often to refresh certificate health metrics.";
    };

    textfileDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/node-exporter-textfile";
      description = "Directory used by node_exporter's textfile collector.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.textfileDir} 0755 root root - -"
    ];

    services.prometheus.exporters.node = {
      enabledCollectors = [ "textfile" ];
      extraFlags = [ "--collector.textfile.directory=${cfg.textfileDir}" ];
    };

    systemd.services.homelab-certificate-metrics = {
      description = "Refresh homelab certificate health metrics";
      after = [ "network.target" ];
      path = with pkgs; [
        coreutils
        openssl
        systemd
      ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        ${certMetricsScript}
      '';
    };

    systemd.timers.homelab-certificate-metrics = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5m";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
    };

    homelab.grafana.dashboards = lib.optionals config.homelab.services.grafana.enable [
      {
        name = "certificate-health.json";
        path = dashboardJson;
      }
    ];
  };
}
