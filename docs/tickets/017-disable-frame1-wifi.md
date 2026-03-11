# Ticket 017: Disable frame1 Wi-Fi

**Status**: DONE
**Created**: 2026-03-11
**Updated**: 2026-03-11

## Task
Disable Wi-Fi on `frame1` so the host uses wired LAN only.

## Implementation Plan
1. Confirm the current network state on `frame1`.
2. Disable Wi-Fi declaratively in the NixOS configuration.
3. Update current deployment and SSH docs to the wired address.

## Work Log
### 2026-03-11
- Confirmed `frame1` was reachable on Wi-Fi (`192.168.2.243`) and ethernet (`192.168.2.22`).
- Traced the `192.168.2.22` SSH failure to asymmetric routing: replies sourced from `.22` were leaving over Wi-Fi.
- Added a declarative Wi-Fi shutdown path so `frame1` stays wired-only after activation and boot.
- Updated current docs and deploy target to use the wired LAN address.
