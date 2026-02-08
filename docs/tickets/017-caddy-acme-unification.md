# Ticket 017: Evaluate Caddy ACME Unification with `security.acme`

**Status**: PLANNING
**Created**: 2026-02-08
**Updated**: 2026-02-08

## Task

Plan and evaluate migration from Caddy-managed ACME certificates to NixOS `security.acme`-managed certificates for web services.

## Implementation Plan

1. Inventory current Caddy DNS challenge flow and dependencies
2. Design target architecture using `security.acme.certs` + Caddy file paths
3. Define rollout and rollback strategy
4. Compare operational risk and cert-renewal behavior
5. Document migration steps and cutover checks

## Notes

- This ticket is intentionally deferred.
- Not blocking MQTT/Zigbee2MQTT/Home Assistant rollout.
- Current approach remains:
  - Caddy handles web certs
  - `security.acme` handles MQTT cert for Mosquitto

## Work Log

### 2026-02-08

- Deferred as separate follow-up by design
- Kept scope out of current smart-home implementation to avoid ingress migration risk
