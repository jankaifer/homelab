# Ticket 037: Frigate Push Notifications

**Status**: DONE
**Created**: 2026-04-26
**Updated**: 2026-04-26

## Task

Move Frigate event notifications toward glanceable mobile push notifications instead of requiring email attachment opens.

## Implementation Plan

Extend the existing MQTT-based Frigate notifier with ntfy delivery while keeping SMTP email as a fallback until the encrypted notification secret contains ntfy topic credentials.

## Work Log

### 2026-04-26

- Added notifier delivery modes: `email`, `ntfy`, `both`, and `auto`.
- In `auto` mode, the notifier sends ntfy push notifications when `NTFY_TOPIC_URL` is available and falls back to email otherwise.
- ntfy notifications upload the annotated Frigate snapshot as the notification attachment and link taps to the Frigate review URL.
- Updated frame1 to use `auto` mode with the existing notifier secret file, so adding `NTFY_TOPIC_URL` and `NTFY_TOKEN` to the secret enables push delivery without another Nix config change.
