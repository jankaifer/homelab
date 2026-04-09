# Mock RTSP camera stream for VM/integration testing
#
# Publishes a generated test-pattern video over RTSP using MediaMTX and ffmpeg.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.mockRtspCamera;
  streamUrl = "rtsp://127.0.0.1:${toString cfg.rtspPort}/${cfg.streamName}";
in
{
  options.homelab.services.mockRtspCamera = {
    enable = lib.mkEnableOption "mock RTSP camera stream";

    streamName = lib.mkOption {
      type = lib.types.str;
      default = "mock-camera";
      description = "RTSP path name for the mock stream.";
    };

    rtspPort = lib.mkOption {
      type = lib.types.port;
      default = 8554;
      description = "Local RTSP port exposed by MediaMTX.";
    };

    width = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1280;
      description = "Video width for the generated stream.";
    };

    height = lib.mkOption {
      type = lib.types.ints.positive;
      default = 720;
      description = "Video height for the generated stream.";
    };

    fps = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Frame rate for the generated stream.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.mediamtx = {
      enable = true;
      settings = {
        rtspAddress = ":${toString cfg.rtspPort}";
        paths.${cfg.streamName} = { };
      };
    };

    systemd.services.mock-rtsp-camera-publisher = {
      description = "Publish a generated RTSP camera stream";
      wantedBy = [ "multi-user.target" ];
      after = [ "mediamtx.service" "network.target" ];
      requires = [ "mediamtx.service" ];
      path = [ pkgs.netcat-openbsd ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 3;
        ExecStartPre = pkgs.writeShellScript "wait-for-mediamtx" ''
          for _ in $(seq 1 30); do
            if nc -z 127.0.0.1 ${toString cfg.rtspPort}; then
              exit 0
            fi
            sleep 1
          done

          echo "MediaMTX did not open RTSP port ${toString cfg.rtspPort} in time." >&2
          exit 1
        '';
        ExecStart = pkgs.writeShellScript "mock-rtsp-camera-publisher" ''
          exec ${lib.getExe pkgs.ffmpeg-headless} \
            -hide_banner \
            -loglevel warning \
            -re \
            -f lavfi -i testsrc2=size=${toString cfg.width}x${toString cfg.height}:rate=${toString cfg.fps} \
            -an \
            -c:v libx264 \
            -pix_fmt yuv420p \
            -preset veryfast \
            -tune zerolatency \
            -g ${toString (cfg.fps * 2)} \
            -f rtsp \
            -rtsp_transport tcp \
            ${lib.escapeShellArg streamUrl}
        '';
      };
    };

    environment.systemPackages = [
      pkgs.ffmpeg-headless
      pkgs.mediamtx
    ];
  };
}
