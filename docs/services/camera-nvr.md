# Camera and NVR Architecture

Architecture decision for a future camera/NVR stack. This is an implementation guide for the next ticket, not an enabled service today.

## Status

**Enabled:** No  
**Decision state:** Architecture selected

## Primary Goal

Incident review comes first:

- retain footage locally for a practical window
- review events after the fact
- keep remote access private

Motion or object detection is a future enhancement, not a day-one requirement.

## Recommended Direction

Start with **Frigate** as the NVR stack on `frame1`.

Why this is the best fit for the current homelab:

- strong Home Assistant integration
- private-first local operation
- works well with RTSP camera streams
- can start without making detection the center of the design
- leaves room to grow into local detection later if hardware justifies it

## Placement

### Initial placement

- run the first NVR deployment on `frame1`
- store recordings on local disk
- keep the stack private behind Tailscale

### Future split trigger

Move to a dedicated node if one or more of these become true:

- more than a few cameras are added
- retention needs start competing with other workloads
- CPU load from transcoding or detection becomes noticeable
- you add accelerator hardware and want camera workloads isolated

## Data Policy

### Backup-worthy

- NVR configuration
- credentials
- camera definitions
- integration settings

### Retention-only

- raw recordings
- rolling event clips unless manually exported for investigation

This keeps the backup system focused on rebuildability and avoids turning video storage into the dominant backup cost.

## Access Model

- remote access stays private via Tailscale
- no public internet exposure in the default architecture
- Home Assistant gets basic stream and entity integration
- Frigate remains the primary camera UI

## Detection and Analytics

- not required for day one
- leave room for later motion or object detection
- do not make accelerator hardware a prerequisite for the first implementation

## Next Implementation Ticket

The implementation ticket should:

1. Add a Frigate module
2. Define recording and config storage paths
3. Route the UI privately through Caddy
4. Add basic Home Assistant integration
5. Keep recordings on local retention-only storage
6. Avoid introducing public exposure or backup of raw footage
