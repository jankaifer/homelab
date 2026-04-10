# Mock RTSP Camera

Mock RTSP camera source for Frigate and camera integration testing.

## Status

**Enabled:** Yes in `frame1-vm` and on `frame1`

## Configuration

**Module:** `modules/services/mock-rtsp-camera.nix`  
**Pattern:** `homelab.services.mockRtspCamera.enable`

**Current VM configuration:**
```nix
homelab.services.mockRtspCamera = {
  enable = true;
  streamName = "mock-driveway";
  rtspPort = 8554;
  width = 1280;
  height = 720;
  fps = 30;
  videoProfile = "detection-demo";
};
```

**Current production configuration:**
```nix
homelab.services.mockRtspCamera = {
  enable = true;
  streamName = "mock-driveway";
  rtspPort = 8554;
  width = 1280;
  height = 720;
  fps = 30;
  videoProfile = "detection-demo";
};
```

## Stream URL

Use this RTSP source inside the VM:

```text
rtsp://127.0.0.1:8554/mock-driveway
```

This is intended for Frigate or other local camera consumers running on the same machine.

## Runtime Model

- `services.mediamtx` provides the RTSP server
- `mock-rtsp-camera-publisher.service` uses `ffmpeg` to loop either a pinned sample clip or a synthetic test pattern
- The default `detection-demo` profile uses Intel's `person-bicycle-car-detection.mp4`, which is much closer to a real driveway/street feed for Frigate testing
- The `detection-demo` path is normalized once during the Nix build, then streamed with `-c:v copy` so the long-running publisher does not keep re-encoding the sample clip on CPU
- The mock publisher now emits a `30` FPS RTSP stream so UI playback stays close to real-time, while Frigate detection remains throttled separately in the camera config
- `test-pattern` remains available when only stream-path validation is needed

## Intended Use

- Frigate integration testing
- Camera pipeline validation without real hardware
- UI, recording, retention-path, and basic object-detection verification before real cameras are added

## Validation

Check the services:
```bash
systemctl status mediamtx mock-rtsp-camera-publisher
```

Probe the RTSP stream:
```bash
ffprobe rtsp://127.0.0.1:8554/mock-driveway
```

Open the stream manually:
```bash
ffplay rtsp://127.0.0.1:8554/mock-driveway
```
