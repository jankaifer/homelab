# Home Assistant Core container module
#
# Runs Home Assistant in Podman with host networking for discovery support.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.homeassistant;
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}"
    + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
  trustedProxyLines = lib.concatMapStringsSep "\n" (proxy: "    - ${proxy}") cfg.trustedProxies;
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

    trustedProxies = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.1" "::1" ];
      description = "Trusted reverse proxy IPs for Home Assistant.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
      "d ${cfg.dataDir}/themes 0750 root root - -"
    ];

    systemd.services.homeassistant-config = {
      description = "Generate Home Assistant configuration";
      wantedBy = [ "podman-homeassistant.service" ];
      before = [ "podman-homeassistant.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail

        install -d -m 0750 ${cfg.dataDir}
        install -d -m 0750 ${cfg.dataDir}/themes

        cat > ${cfg.dataDir}/configuration.yaml <<'EOF'
        # Managed by Nix. Put local overrides in dedicated includes or module options.
        default_config:

        frontend:
          themes: !include_dir_merge_named themes

        automation: !include automations.yaml
        script: !include scripts.yaml
        scene: !include scenes.yaml

        http:
          use_x_forwarded_for: true
          trusted_proxies:
        ${trustedProxyLines}
        EOF

        touch ${cfg.dataDir}/automations.yaml
        touch ${cfg.dataDir}/scripts.yaml
        touch ${cfg.dataDir}/scenes.yaml

        touch ${cfg.dataDir}/secrets.yaml

        chmod 0640 ${cfg.dataDir}/configuration.yaml ${cfg.dataDir}/automations.yaml ${cfg.dataDir}/scripts.yaml ${cfg.dataDir}/scenes.yaml ${cfg.dataDir}/secrets.yaml
      '';
    };

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

    systemd.services.podman-homeassistant = {
      requires = [ "homeassistant-config.service" ];
      after = [ "homeassistant-config.service" "mosquitto.service" ];
      restartTriggers = [
        config.systemd.services.homeassistant-config.script
      ];
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} =
      "reverse_proxy localhost:${toString cfg.port}";

    homelab.homepage.services = [{
      name = "Home Assistant";
      category = "Smart Home";
      description = "Home automation platform";
      href = homepageHref;
      icon = "home-assistant";
    }];
  };
}
