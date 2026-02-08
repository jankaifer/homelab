# Home Assistant Core container module
#
# Runs Home Assistant in Podman with host networking for discovery support.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.homeassistant;
in
{
  options.homelab.services.homeassistant = {
    enable = lib.mkEnableOption "Home Assistant Core container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/home-assistant/home-assistant:2025.2.5";
      description = "Container image for Home Assistant Core.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Home Assistant HTTP port (inside host network mode).";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "home.frame1.hobitin.eu";
      description = "Domain for Home Assistant via Caddy.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/homeassistant";
      description = "Persistent Home Assistant configuration directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
    ];

    virtualisation.oci-containers.containers.homeassistant = {
      image = cfg.image;
      autoStart = true;
      autoRemoveOnStop = false;
      pull = "missing";
      volumes = [
        "${cfg.dataDir}:/config"
        "/etc/localtime:/etc/localtime:ro"
      ];
      extraOptions = [
        "--network=host"
        "--restart=unless-stopped"
      ];
    };

    systemd.services.podman-homeassistant.serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 5;
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} =
      "reverse_proxy localhost:${toString cfg.port}";

    homelab.homepage.services = [{
      name = "Home Assistant";
      category = "Smart Home";
      description = "Home automation platform";
      href = "https://${cfg.domain}:8443";
      icon = "home-assistant";
    }];
  };
}
