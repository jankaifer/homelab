# VM-specific configuration
#
# This module adds settings needed for local VM testing:
# - Mounts host SSH keys via virtfs so agenix can decrypt secrets
# - Only included in server-vm configuration, not production
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Import qemu-vm module to get virtualisation options
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ../../modules/services/mock-rtsp-camera.nix
  ];

  # Share host's SSH directory into VM via virtfs/9p
  # The host path (/host-ssh) is mounted from Mac's ~/.ssh by Docker
  virtualisation.sharedDirectories = {
    hostssh = {
      source = "/host-ssh";
      target = "/mnt/host-ssh";
    };
  };

  # Tell agenix to use the host's SSH key for decryption
  # This key is mounted from the Mac via Docker -> QEMU virtfs chain
  age.identityPaths = [ "/mnt/host-ssh/id_ed25519" ];

  # VM testing should use Caddy's internal CA instead of mutating real DNS
  # records or waiting on external ACME issuance.
  homelab.services.caddy = {
    localTls = lib.mkForce true;
    cloudflareDns.enable = lib.mkForce false;
  };

  # Dashboard cards need the host-mapped HTTPS port during VM testing.
  homelab.services.homepage.publicHttpsPort = lib.mkForce 8443;

  # Keep VM evaluation/builds usable without a real Zigbee coordinator.
  homelab.services.zigbee2mqtt.allowPlaceholderSerialPort = lib.mkForce true;

  # Production-only operational jobs stay off in the VM.
  homelab.services.backup.enable = lib.mkForce false;
  homelab.services.certMonitoring.enable = lib.mkForce false;

  # The NAS stack is production-focused and not useful in the local VM.
  homelab.services.nas.enable = lib.mkForce false;

  # Mock camera feed for Frigate and camera-integration testing in the VM.
  homelab.services.mockRtspCamera = {
    enable = true;
    streamName = "mock-driveway";
    rtspPort = 8554;
    width = 1280;
    height = 720;
    fps = 10;
  };

  # Use the mock RTSP camera to exercise the Frigate integration path in the VM.
  homelab.services.frigate = {
    enable = lib.mkForce true;
    recordingsDir = lib.mkForce "/var/lib/frigate-test-media";
    cameras.mock_driveway = {
      ffmpeg.inputs = [{
        path = "rtsp://127.0.0.1:8554/mock-driveway";
        input_args = "preset-rtsp-restream";
        roles = [ "detect" "record" ];
      }];
      detect = {
        enabled = false;
        width = 1280;
        height = 720;
        fps = 5;
      };
    };
    extraSettings.birdseye.enabled = false;
  };
}
