# frame1 machine configuration
# This is the main entry point for frame1's NixOS config
{ config, pkgs, lib, ... }:

let
  sshKeys = import ../../lib/ssh-keys.nix;
  allUserKeys = builtins.attrValues sshKeys;
in
{
  imports = [
    ./hardware.nix
    ./disko.nix
    # Service modules - import all, enable selectively below
    ../../modules/services/caddy.nix
    ../../modules/services/homepage.nix
    ../../modules/services/victoriametrics.nix
    ../../modules/services/loki.nix
    ../../modules/services/alloy.nix
    ../../modules/services/grafana.nix
    ../../modules/services/nas.nix
    ../../modules/services/tailscale.nix
    ../../modules/services/backup.nix
    ../../modules/services/cert-monitoring.nix
    ../../modules/services/mosquitto.nix
    ../../modules/services/zigbee2mqtt.nix
    ../../modules/services/homeassistant.nix
    ../../modules/services/frigate.nix
    ../../modules/services/mock-rtsp-camera.nix
  ];

  # Basic system settings
  system.stateVersion = "24.05";
  networking.hostName = "frame1";

  # Nix settings for flake workflows and remote builds
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "jankaifer" ];
  };

  # Allow unfree packages if needed (for things like nvidia drivers, etc)
  nixpkgs.config.allowUnfree = true;

  # Timezone - adjust to your location
  time.timeZone = "Europe/Prague";

  # Basic networking
  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [ "type:wifi" ];

  # Enable the Intel iGPU render stack so Frigate can offload video decode
  # through VA-API instead of burning CPU on ffmpeg.
  hardware.graphics = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 {
    enable = true;
    extraPackages = [ pkgs.intel-media-driver ];
  };

  # Frame1 should stay wired-only in production. Leaving both Wi-Fi and
  # ethernet active on the same LAN caused asymmetric routing and broke SSH
  # over the wired address.
  systemd.services.disable-frame1-wifi = {
    description = "Disable Wi-Fi on frame1";
    after = [ "NetworkManager.service" ];
    wants = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.networkmanager}/bin/nmcli radio wifi off";
    };
  };

  # Podman runtime for OCI containers (Home Assistant and Zigbee2MQTT)
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
    oci-containers.backend = "podman";
  };

  # SSH server - essential for remote management
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no"; # Disable direct root SSH login
      PasswordAuthentication = false; # Enforce SSH key-only auth
      AllowUsers = [ "jankaifer" ]; # Restrict SSH access to main operator
    };
  };

  # Firewall - open SSH port
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # Root user
  users.users.root = {
    openssh.authorizedKeys.keys = allUserKeys;
  };

  # Main operator account
  users.users.jankaifer = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = allUserKeys;
  };

  # Allow wheel group to sudo without password (convenient for testing)
  security.sudo.wheelNeedsPassword = false;

  # Essential packages available system-wide
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
  ];

  # ===================
  # Secrets (agenix)
  # ===================
  # Secrets are age-encrypted and decrypted at boot time.
  # VM: Uses host's SSH key mounted via virtfs (see vm.nix)
  # Production: Uses server's SSH host key (add to secrets.nix first)

  age.secrets = {
    cloudflare-api-token = {
      file = ../../secrets/cloudflare-api-token.age;
      owner = "caddy";
      group = "caddy";
    };
    grafana-admin-password = {
      file = ../../secrets/grafana-admin-password.age;
      owner = "grafana";
      group = "grafana";
    };
    tailscale-auth-key = {
      file = ../../secrets/tailscale-auth-key.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    mqtt-homeassistant-password = {
      file = ../../secrets/mqtt-homeassistant-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    mqtt-zigbee2mqtt-password = {
      file = ../../secrets/mqtt-zigbee2mqtt-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    mqtt-frigate-password = {
      file = ../../secrets/mqtt-frigate-password.age;
      owner = "frigate";
      group = "frigate";
      mode = "0400";
    };
    restic-password = {
      file = ../../secrets/restic-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    restic-repository-env = {
      file = ../../secrets/restic-repository-env.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    nas-jankaifer-password = {
      file = ../../secrets/nas-jankaifer-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
    nas-guest-password = {
      file = ../../secrets/nas-guest-password.age;
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  # ===================
  # Services
  # ===================

  # Homepage dashboard - only accessible through Caddy reverse proxy
  homelab.services.homepage = {
    enable = true;
    port = 3000;
    openFirewall = false; # Access through Caddy only
    allowedHosts = [ "local.hobitin.eu" "local.hobitin.eu:8443" "frame1.hobitin.eu" ];
  };

  # Caddy reverse proxy - entry point for all web services
  homelab.services.caddy = {
    enable = true;
    acmeEmail = "jan@kaifer.cz"; # For Let's Encrypt registration

    # Use Cloudflare DNS challenge for real certificates
    cloudflareDns = {
      enable = true;
      apiTokenFile = config.age.secrets.cloudflare-api-token.path;
    };

    virtualHosts = {
      "local.hobitin.eu" = "reverse_proxy localhost:3000";
      "frame1.hobitin.eu" = "reverse_proxy localhost:3000";
    };
  };

  # VictoriaMetrics - metrics collection (Prometheus-compatible, more efficient)
  homelab.services.victoriametrics = {
    enable = true;
    # nodeExporter.enable = true; # Default, collects system metrics
    # retentionPeriod = "15d"; # Default
    domain = "metrics.frame1.hobitin.eu";
  };

  # Loki - log storage
  homelab.services.loki = {
    enable = true;
    # retentionPeriod = "360h"; # Default, 15 days
    # domain = "logs.local.hobitin.eu"; # Default
  };

  # Alloy - telemetry collector (logs, metrics, traces)
  homelab.services.alloy = {
    enable = true;
    # logs.enable = true; # Default, ships systemd journal to Loki
  };

  # Grafana - dashboards and visualization
  homelab.services.grafana = {
    enable = true;
    # port = 3001; # Default
    domain = "grafana.frame1.hobitin.eu";
    adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  };

  homelab.services.nas = {
    enable = true;
    rootPath = "/nas";
    lanCidr = "192.168.2.0/24";
    tailscaleCidr = "100.64.0.0/10";
    adminSmbPasswordFile = config.age.secrets.nas-jankaifer-password.path;
    guestSmbPasswordFile = config.age.secrets.nas-guest-password.path;
  };

  # Tailscale - VPN for remote access (autologin via auth key secret)
  homelab.services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
    acceptDns = false;
    # acceptRoutes = false; # Default, reflected in auto up flags
    # exitNode = false; # Default
  };

  homelab.services.backup = {
    enable = true;
    repositoryEnvFile = config.age.secrets.restic-repository-env.path;
    passwordFile = config.age.secrets.restic-password.path;
  };

  homelab.services.certMonitoring = {
    enable = true;
    warningDays = 14;
  };

  # Mosquitto - TLS broker for Home Assistant and Zigbee2MQTT
  homelab.services.mosquitto = {
    enable = true;
    acmeEmail = "jan@kaifer.cz";
    cloudflareDnsTokenFile = config.age.secrets.cloudflare-api-token.path;
    homeAssistantPasswordFile = config.age.secrets.mqtt-homeassistant-password.path;
    zigbee2mqttPasswordFile = config.age.secrets.mqtt-zigbee2mqtt-password.path;
    frigatePasswordFile = config.age.secrets.mqtt-frigate-password.path;
    loopbackPort = 1883;
    allowLAN = true;
    allowTailscale = true;
  };

  # Zigbee2MQTT - Sonoff coordinator bridge (containerized)
  homelab.services.zigbee2mqtt = {
    enable = true;
    serialPort = "/dev/serial/by-id/usb-ITEAD_SONOFF_Zigbee_3.0_USB_Dongle_Plus_V2_20231101183952-if00";
    adapter = "ember"; # Sonoff ZBDongle-E default
    mqtt.passwordFile = config.age.secrets.mqtt-zigbee2mqtt-password.path;
  };

  # Home Assistant Core (containerized, host networking for discovery)
  homelab.services.homeassistant = {
    enable = true;
  };

  # Synthetic RTSP source for Frigate integration work until real cameras
  # are configured.
  homelab.services.mockRtspCamera = {
    enable = true;
    streamName = "mock-driveway";
    rtspPort = 8554;
    width = 1280;
    height = 720;
    fps = 10;
  };

  # Frigate is enabled in production against the synthetic RTSP source so the
  # private UI, storage path, and service plumbing can be verified end to end.
  homelab.services.frigate = {
    enable = true;
    domain = "frigate.frame1.hobitin.eu";
    recordingsDir = "/nas/nvr/frigate";
    retainDays = 3;
    reviewRetainDays = 14;
    cameras.mock_driveway = {
      ffmpeg.inputs = [{
        path = "rtsp://127.0.0.1:8554/mock-driveway";
        input_args = "preset-rtsp-restream";
        roles = [ "detect" "record" ];
      }];
      detect = {
        enabled = true;
        width = 1280;
        height = 720;
        fps = 1;
      };
    };
    extraSettings = {
      birdseye.enabled = false;
      ffmpeg.hwaccel_args = "preset-vaapi";
      objects.track = [ "person" "car" "bicycle" ];
    };
    snapshots = {
      retainDays = 7;
      cleanCopy = false;
    };
    mqtt = {
      enable = true;
      host = "127.0.0.1";
      port = 1883;
      passwordFile = config.age.secrets.mqtt-frigate-password.path;
    };
  };

  services.frigate.vaapiDriver = lib.mkIf pkgs.stdenv.hostPlatform.isx86_64 "iHD";
}
