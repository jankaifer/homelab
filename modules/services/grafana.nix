# Grafana dashboards and visualization module
#
# Grafana provides dashboards for metrics (VictoriaMetrics) and logs (Loki).
# Main observability UI for the homelab.
#
# Access: grafana.local.hobitin.eu (via Caddy reverse proxy)
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.grafana;
  victoriametricsCfg = config.homelab.services.victoriametrics;
  lokiCfg = config.homelab.services.loki;
  dashboardEntries = config.homelab.grafana.dashboards;
  provisionedDatasources =
    lib.optional victoriametricsCfg.enable {
      name = "VictoriaMetrics";
      uid = "victoriametrics";
      type = "prometheus";
      url = "http://127.0.0.1:${toString victoriametricsCfg.port}";
      isDefault = true;
      editable = false;
    }
    ++ lib.optional lokiCfg.enable {
      name = "Loki";
      uid = "loki";
      type = "loki";
      url = "http://127.0.0.1:${toString lokiCfg.port}";
      editable = false;
    };
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}"
    + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
  dashboardDir = pkgs.linkFarm "grafana-dashboards" dashboardEntries;
in
{
  options.homelab.grafana.dashboards = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Filename for the provisioned Grafana dashboard.";
        };

        path = lib.mkOption {
          type = lib.types.path;
          description = "Path to the dashboard JSON file.";
        };
      };
    });
    default = [ ];
    description = "Dashboards to provision into Grafana.";
  };

  options.homelab.services.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3001; # Grafana default is 3000, but Homepage uses that
      description = "Port for Grafana web UI";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "grafana.local.hobitin.eu";
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

    oidc = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Authelia OIDC login";
      };

      issuerUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://auth.frame1.hobitin.eu";
        description = "Authelia issuer URL";
      };

      clientId = lib.mkOption {
        type = lib.types.str;
        default = "grafana";
        description = "OIDC client ID registered in Authelia";
      };

      clientSecretFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to file containing the Grafana OIDC client secret";
      };

      roleAttributePath = lib.mkOption {
        type = lib.types.str;
        default = "contains(groups[*], 'admins') && 'Admin' || contains(groups[*], 'grafana-editors') && 'Editor' || 'Viewer'";
        description = "Grafana JMESPath role mapping expression for Authelia groups";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (!cfg.oidc.enable) || cfg.oidc.clientSecretFile != null;
        message = "homelab.services.grafana.oidc.clientSecretFile is required when Grafana OIDC is enabled";
      }
    ];

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

        auth = {
          disable_login_form = false;
          oauth_auto_login = false;
        };

        "auth.generic_oauth" = lib.mkIf cfg.oidc.enable {
          enabled = true;
          name = "Authelia";
          icon = "signin";
          client_id = cfg.oidc.clientId;
          client_secret = "$__file{${cfg.oidc.clientSecretFile}}";
          scopes = "openid profile email groups";
          empty_scopes = false;
          auth_url = "${cfg.oidc.issuerUrl}/api/oidc/authorization";
          token_url = "${cfg.oidc.issuerUrl}/api/oidc/token";
          api_url = "${cfg.oidc.issuerUrl}/api/oidc/userinfo";
          login_attribute_path = "preferred_username";
          groups_attribute_path = "groups";
          name_attribute_path = "name";
          use_pkce = true;
          role_attribute_path = cfg.oidc.roleAttributePath;
          auth_style = "InHeader";
          allow_sign_up = true;
          skip_org_role_sync = false;
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

        datasources.settings = {
          prune = true;
          deleteDatasources = map (datasource: {
            name = datasource.name;
            orgId = 1;
          }) provisionedDatasources;
          datasources = provisionedDatasources;
        };

        dashboards.settings = lib.mkIf (dashboardEntries != [ ]) {
          apiVersion = 1;
          providers = [{
            name = "homelab";
            type = "file";
            options.path = dashboardDir;
          }];
        };
      };
    };

    # Register with Caddy reverse proxy
    homelab.services.caddy.virtualHosts.${cfg.domain} = "reverse_proxy 127.0.0.1:${toString cfg.port}";

    # Register with Homepage dashboard
    homelab.homepage.services = [{
      name = "Grafana";
      category = "Monitoring";
      description = "Dashboards & Visualization";
      href = homepageHref;
      icon = "grafana";
    }];
  };
}
