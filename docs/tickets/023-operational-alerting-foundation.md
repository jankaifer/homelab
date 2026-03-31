# Ticket 023: Operational Alerting Foundation

**Status**: PLANNING
**Created**: 2026-03-31
**Updated**: 2026-03-31

## Task

Add active operational alerting on top of the backup and certificate visibility that already exists. The goal is to move from dashboards-only observability to actionable notifications for failures that need attention.

## Implementation Plan

1. Define the initial alert set for the current homelab:
   - backup job failures
   - backup freshness gaps
   - certificate expiry horizon breaches
   - certificate renewal-unit failures
2. Choose the notification path aligned with the project plan's email-first alerting direction
3. Implement alert rules and delivery wiring in the existing monitoring stack
4. Document alert meanings, response expectations, and common remediation steps
5. Validate that test alerts can be generated and received

## Notes

- This is the next-step follow-up to the visibility added in Tickets 019 and 020.
- Scope is intentionally narrow: practical alerts for existing services first, not a full incident-management system.

## Work Log

### 2026-03-31

- Ticket created from the project plan's next execution candidates.
- Framed as reliability work that builds directly on the current observability baseline.
