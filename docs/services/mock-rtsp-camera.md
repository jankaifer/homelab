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
  fps = 10;
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
  fps = 10;
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
- `mock-rtsp-camera-publisher.service` uses `ffmpeg` to generate a continuous test-pattern video
- The stream is deterministic and does not depend on any physical camera device

## Intended Use

- Frigate integration testing
- Camera pipeline validation without real hardware
- UI, recording, and retention-path verification before real cameras are added

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
