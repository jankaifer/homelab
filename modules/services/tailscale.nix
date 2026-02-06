# Tailscale VPN module
#
# Tailscale creates a secure mesh VPN using WireGuard.
# Provides remote access to homelab services without port forwarding.
#
# Setup:
# 1. Enable this module
# 2. Optionally provide authKeyFile for unattended login
# 3. Deploy to server
# 4. Install Tailscale on laptop/phone and authenticate
# 5. Access services via Tailscale IP or MagicDNS name
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.tailscale;
in
{
  options.homelab.services.tailscale = {
    enable = lib.mkEnableOption "Tailscale VPN";

    acceptRoutes = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Accept subnet routes advertised by other Tailscale nodes";
    };

    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to a Tailscale auth key file for unattended login";
    };

    exitNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise this machine as an exit node (route all traffic through it)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Tailscale service
    services.tailscale = {
      enable = true;
      useRoutingFeatures = lib.mkIf cfg.exitNode "server";
      authKeyFile = lib.mkIf (cfg.authKeyFile != null) cfg.authKeyFile;
      extraUpFlags = lib.mkIf (cfg.authKeyFile != null) [
        "--accept-routes=${lib.boolToString cfg.acceptRoutes}"
      ];
    };

    # Open firewall for Tailscale
    networking.firewall = {
      # Allow Tailscale UDP port
      allowedUDPPorts = [ config.services.tailscale.port ];

      # Allow traffic from Tailscale network
      trustedInterfaces = [ "tailscale0" ];

      # Allow forwarding if exit node is enabled
      checkReversePath = lib.mkIf cfg.exitNode "loose";
    };

    # Ensure Tailscale starts on boot
    systemd.services.tailscaled = {
      wantedBy = [ "multi-user.target" ];
    };
  };
}
