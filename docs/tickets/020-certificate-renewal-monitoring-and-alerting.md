# Ticket 020: Certificate Renewal Monitoring and Alerting

**Status**: PLANNING
**Created**: 2026-03-27
**Updated**: 2026-03-27

## Task

Add monitoring and alerting for certificate renewal so TLS failures are detected before they turn into service outages. This should cover both the main Caddy-managed web certificates and the MQTT ACME flow.

## Implementation Plan

1. Inventory all certificate issuance and renewal paths in the repo
2. Define what should be monitored:
   - renewal job failures
   - certificate expiration horizon
   - missing certificate files for dependent services
3. Expose those signals into the existing observability stack
4. Add an alert delivery path suitable for the homelab operating model
5. Document how to investigate and remediate renewal failures

## Notes

- The immediate motivation is the deferred follow-up called out in the deployment ticket.
- MQTT ACME deserves explicit coverage because it is separate from the main Caddy path.

## Work Log

### 2026-03-27

- Ticket created from roadmap work selection.
- Positioned as reliability work rather than feature expansion.
