# Mock RTSP camera stream for VM/integration testing
#
# Publishes either a realistic detection-oriented sample clip or a synthetic
# test pattern over RTSP using MediaMTX and ffmpeg.
{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.services.mockRtspCamera;
  streamUrl = "rtsp://127.0.0.1:${toString cfg.rtspPort}/${cfg.streamName}";
  personVehicleDemo = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/intel-iot-devkit/sample-videos/master/person-bicycle-car-detection.mp4";
    hash = "sha256-RSsRt+DvvQGfHZVw0MeQ6QQWrUrSnuxgA4ctCEQxQO8=";
  };
  sourceInput =
    if cfg.videoProfile == "detection-demo" then
      "-stream_loop -1 -re -i ${lib.escapeShellArg personVehicleDemo}"
    else
      "-re -f lavfi -i ${lib.escapeShellArg "testsrc2=size=${toString cfg.width}x${toString cfg.height}:rate=${toString cfg.fps}"}";
  videoFilter = lib.escapeShellArg
    "fps=${toString cfg.fps},scale=${toString cfg.width}:${toString cfg.height}:force_original_aspect_ratio=decrease,pad=${toString cfg.width}:${toString cfg.height}:(ow-iw)/2:(oh-ih)/2";
  normalizedDetectionDemo = pkgs.runCommand "mock-rtsp-camera-detection-demo-${toString cfg.width}x${toString cfg.height}-${toString cfg.fps}fps.mp4"
    {
      nativeBuildInputs = [ pkgs.ffmpeg-headless ];
    } ''
      ffmpeg -hide_banner -loglevel error \
        -stream_loop 1 \
        -i ${lib.escapeShellArg personVehicleDemo} \
        -an \
        -c:v libx264 \
        -pix_fmt yuv420p \
        -preset veryfast \
        -profile:v baseline \
        -level 3.1 \
        -g ${toString (cfg.fps * 2)} \
        -movflags +faststart \
        -vf ${videoFilter} \
        -r ${toString cfg.fps} \
        -y "$out"
    '';
  publisherSourceInput =
    if cfg.videoProfile == "detection-demo" then
      "-stream_loop -1 -re -i ${lib.escapeShellArg normalizedDetectionDemo}"
    else
      sourceInput;
  publisherVideoArgs =
    if cfg.videoProfile == "detection-demo" then
      "-c:v copy"
    else
      ''
        -c:v libx264
        -pix_fmt yuv420p
        -preset veryfast
        -tune zerolatency
        -g ${toString (cfg.fps * 2)}
        -vf ${videoFilter}
      '';
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

    videoProfile = lib.mkOption {
      type = lib.types.enum [ "detection-demo" "test-pattern" ];
      default = "detection-demo";
      description = ''
        Video source used for the mock stream. `detection-demo` loops a pinned
        sample clip with people, bicycles, and cars. `test-pattern` keeps the
        synthetic lavfi source for pure stream-path testing.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.mediamtx = {
      enable = true;
      settings = {
        rtmp = false;
        hls = false;
        webrtc = false;
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
            ${publisherSourceInput} \
            -an \
            ${publisherVideoArgs} \
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
