# Ticket 020: Certificate Renewal Monitoring and Alerting

**Status**: IN_PROGRESS
**Created**: 2026-03-27
**Updated**: 2026-03-27

## Task

Add observability for certificate renewal so TLS failures are detected before they turn into service outages. This covers both the main Caddy-managed web certificates and the MQTT ACME flow, with Grafana visibility first and active alerting deferred.

## Implementation Plan

1. Inventory all certificate issuance and renewal paths in the repo
2. Define what should be monitored:
   - renewal job failures
   - certificate expiration horizon
   - missing certificate files for dependent services
3. Expose those signals into the existing observability stack
4. Provision a Grafana dashboard for day-to-day visibility
5. Document how to investigate and remediate renewal failures

## Notes

- The immediate motivation is the deferred follow-up called out in the deployment ticket.
- MQTT ACME deserves explicit coverage because it is separate from the main Caddy path.

## Work Log

### 2026-03-27

- Ticket created from roadmap work selection.
- Positioned as reliability work rather than feature expansion.
- Added `modules/services/cert-monitoring.nix` and enabled it on `frame1`.
- Implemented a systemd timer that writes certificate and renewal-unit metrics into node exporter's textfile collector.
- Added automatic Grafana dashboard provisioning for `Certificate Health`.
- Kept email or other active alerting out of scope for v1.
- Remaining work: validate metrics and dashboard rendering on a running deployment.
