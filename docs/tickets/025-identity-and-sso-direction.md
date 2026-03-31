# Ticket 025: Identity and SSO Direction

**Status**: PLANNING
**Created**: 2026-03-31
**Updated**: 2026-03-31

## Task

Evaluate and define the homelab identity and SSO direction for the point where service count and family usage justify centralized authentication. The goal is to pick an operating model and adoption path before any implementation-specific rollout.

## Implementation Plan

1. List the services and user flows that would benefit from shared identity
2. Evaluate candidate approaches appropriate for the homelab's scale and operational budget
3. Decide the boundary between centralized auth, local service auth, and Tailscale-based access
4. Define migration sequencing and which services, if any, should move first
5. Capture a recommended implementation path and deferred concerns

## Notes

- This is intentionally an architecture and adoption-direction ticket first, not an implementation ticket.
- The project plan treats SSO as a later-stage capability tied to service growth.

## Work Log

### 2026-03-31

- Ticket created from the project plan's deferred identity/SSO work.
- Kept architecture-first to avoid prematurely committing to a stack before the need is concrete.
