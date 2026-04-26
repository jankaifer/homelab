{ config, lib, ... }:

let
  cfg = config.homelab.services.akkudoktorEos;
  homepageHttpsPort = lib.attrByPath [ "homelab" "services" "homepage" "publicHttpsPort" ] null config;
  homepageHref = "https://${cfg.domain}"
    + lib.optionalString (homepageHttpsPort != null) ":${toString homepageHttpsPort}";
in
{
  options.homelab.services.akkudoktorEos = {
    enable = lib.mkEnableOption "Akkudoktor-EOS optimizer API";

    image = lib.mkOption {
      type = lib.types.str;
      default = "akkudoktor/eos:latest";
      description = "Container image for Akkudoktor-EOS.";
    };

    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8503;
      description = "Host-local EOS API port.";
    };

    dashboardPort = lib.mkOption {
      type = lib.types.port;
      default = 8504;
      description = "Host-local EOS dashboard port.";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "eos.frame1.hobitin.eu";
      description = "Domain for the EOS dashboard via Caddy.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/akkudoktor-eos";
      description = "Persistent EOS data directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
    ];

    virtualisation.oci-containers.containers.akkudoktor-eos = {
      image = cfg.image;
      autoStart = true;
      autoRemoveOnStop = false;
      pull = "missing";
      ports = [
        "127.0.0.1:${toString cfg.apiPort}:8503"
        "127.0.0.1:${toString cfg.dashboardPort}:8504"
      ];
      volumes = [
        "${cfg.dataDir}:/data:rw"
      ];
      environment = {
        OPENBLAS_NUM_THREADS = "1";
        OMP_NUM_THREADS = "1";
        MKL_NUM_THREADS = "1";
        PIP_PROGRESS_BAR = "off";
        PIP_NO_COLOR = "1";
        EOS_SERVER__HOST = "0.0.0.0";
        EOS_SERVER__PORT = "8503";
        EOS_SERVER__EOSDASH_HOST = "0.0.0.0";
        EOS_SERVER__EOSDASH_PORT = "8504";
        EOS_SERVER__EOSDASH_SESSKEY = "homelab-eos-dashboard";
        DOCKER_COMPOSE_DATA_DIR = "/data";
      };
      extraOptions = [
        "--ulimit=nproc=65535:65535"
        "--ulimit=nofile=65535:65535"
        "--security-opt=seccomp=unconfined"
        "--restart=unless-stopped"
      ];
    };

    systemd.services.podman-akkudoktor-eos.serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 5;
    };

    homelab.services.caddy.virtualHosts.${cfg.domain} =
      "reverse_proxy 127.0.0.1:${toString cfg.dashboardPort}";

    homelab.homepage.services = [{
      name = "Akkudoktor EOS";
      category = "Smart Home";
      description = "Read-only energy optimizer";
      href = homepageHref;
      icon = "mdi-lightning-bolt";
    }];
  };
}
