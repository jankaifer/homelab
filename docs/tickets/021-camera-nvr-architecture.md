# Ticket 021: Camera and NVR Architecture

**Status**: DONE
**Created**: 2026-03-27
**Updated**: 2026-03-27

## Task

Design the camera/NVR direction for the homelab before introducing implementation-specific modules. The goal is to decide the operating model, storage requirements, retention, network placement, and integration points without prematurely committing to a stack.

## Implementation Plan

1. Define the use cases:
   - live view
   - recording
   - motion or event retention
   - remote access expectations
2. Evaluate candidate architectures and products
3. Estimate storage, retention, and backup expectations
4. Decide network and security boundaries for cameras and recorder
5. Capture a recommended next-step implementation plan

## Decision Areas

- Whether cameras should remain entirely local and private
- Whether the recorder belongs on `frame1` or a future dedicated node
- Whether recordings are backup-worthy or treated as retention-only data
- Which Home Assistant integrations matter on day one

## Work Log

### 2026-03-27

- Ticket created from roadmap work selection.
- Kept intentionally architecture-first because the long-term plan still targets a small multi-node fleet.
- Captured the architecture decision in `docs/services/camera-nvr.md`.
- Chose Frigate as the recommended direction for a first implementation on `frame1`.
- Locked the access model to private Tailscale access and treated recordings as retention-only data.
- Scoped Home Assistant integration to basic entity and stream integration rather than deep automation coupling.
