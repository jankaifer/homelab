# Homepage dashboard module
#
# Homepage is a simple, customizable dashboard for your homelab services.
# https://gethomepage.dev/
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.homepage;
in
{
  options.homelab.services.homepage = {
    enable = lib.mkEnableOption "Homepage dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for Homepage dashboard";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall port (usually not needed if behind Caddy)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.port;

      # Basic settings - can be expanded later
      settings = {
        title = "Homelab";
        background = {
          image = "";
          blur = "sm";
          opacity = 50;
        };
      };

      # Services shown on the dashboard
      # This will be expanded as we add more services
      services = [
        {
          "Infrastructure" = [
            {
              "Grafana" = {
                description = "Metrics & Dashboards";
                href = "http://localhost:3001"; # Will be updated when Grafana is added
                icon = "grafana";
              };
            }
          ];
        }
      ];

      # Widgets at the top of the page
      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
            disk = "/";
          };
        }
        {
          search = {
            provider = "duckduckgo";
            target = "_blank";
          };
        }
      ];
    };

    # Optionally open firewall
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
  };
}
