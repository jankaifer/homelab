# Homepage dashboard module
#
# Homepage is a simple, customizable dashboard for your homelab services.
# https://gethomepage.dev/
#
# Services register themselves via homelab.homepage.services option.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.homepage;
  homepageCfg = config.homelab.homepage;

  # Group services by category
  groupedServices = lib.foldl' (acc: svc:
    acc // {
      ${svc.category} = (acc.${svc.category} or [ ]) ++ [{
        ${svc.name} = {
          inherit (svc) description href icon;
        } // (lib.optionalAttrs (svc.widget != null) { widget = svc.widget; });
      }];
    }
  ) {} homepageCfg.services;

  # Convert to Homepage format
  servicesConfig = lib.mapAttrsToList (category: svcs: { ${category} = svcs; }) groupedServices;
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

    allowedHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "lan.kaifer.dev" "homepage.local" ];
      description = "Allowed hostnames for Homepage (for reverse proxy setups)";
    };
  };

  # Shared option for services to register themselves on the dashboard
  options.homelab.homepage.services = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "Service name displayed on dashboard";
        };
        category = lib.mkOption {
          type = lib.types.str;
          default = "Services";
          description = "Category to group this service under";
        };
        description = lib.mkOption {
          type = lib.types.str;
          description = "Short description of the service";
        };
        href = lib.mkOption {
          type = lib.types.str;
          description = "URL to the service";
        };
        icon = lib.mkOption {
          type = lib.types.str;
          description = "Icon name (from dashboard-icons or URL)";
        };
        widget = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = null;
          description = "Optional widget configuration";
        };
      };
    });
    default = [ ];
    description = "Services to display on the Homepage dashboard. Each service module can add to this list.";
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

      # Services are registered by individual service modules via homelab.homepage.services
      services = servicesConfig;

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

    # Set allowed hosts for reverse proxy setups (merge with NixOS defaults)
    systemd.services.homepage-dashboard.environment.HOMEPAGE_ALLOWED_HOSTS = lib.mkIf (cfg.allowedHosts != [ ]) (
      lib.mkForce (lib.concatStringsSep "," cfg.allowedHosts)
    );
  };
}
