# Ticket 033: Energy Stack Integration Architecture

**Status**: PLANNING
**Created**: 2026-04-26
**Updated**: 2026-04-26

## Task

Define the integration architecture for replacing the bespoke energy scheduler with an existing stack based on evcc, Akkudoktor-EOS, EOS Connect, Home Assistant, and MQTT.

## Implementation Plan

Use the hybrid architecture:

1. evcc owns EV charging and loadpoint control.
2. Home Assistant owns household device integration, including heat pump, sensors, helpers, and local automations.
3. Akkudoktor-EOS runs as the optimizer API.
4. EOS Connect orchestrates between Home Assistant, evcc, EOS, and MQTT.
5. MQTT is used for state propagation, observability, dashboards, and explicit override topics, but not as the only command/control path.

Core control paths:

- EV charging commands flow from EOS Connect to evcc through evcc's direct API where supported.
- Heat pump and household device commands flow from EOS Connect to Home Assistant.
- Optimization requests flow from EOS Connect to Akkudoktor-EOS over HTTP.
- MQTT carries telemetry and selected override/status topics for loose coupling and inspection.

The implementation should avoid competing command paths. In particular, do not let Home Assistant automations, MQTT subscribers, and EOS Connect all command evcc independently.

Follow-up implementation tickets:

1. Add evcc service wrapper and expose it through Caddy/Homepage.
2. Add Akkudoktor-EOS OCI service and expose API/dashboard through Caddy/Homepage.
3. Add EOS Connect OCI service and wire it to evcc, EOS, Home Assistant, and Mosquitto.
4. Remove the repo-local energy-scheduler code, UI, service modules, scripts, tests, and docs once the replacement stack is in place.

## Work Log

### 2026-04-26

- Compared three integration approaches:
  - MQTT-only command and state bus.
  - Hybrid direct-authority model with MQTT for state and observability.
  - Alternative topologies centered on Home Assistant, evcc-direct integration, evcc+EOS without EOS Connect, or dashboard-only deployment.
- Chose the hybrid architecture because it preserves clear ownership:
  - evcc remains authoritative for charger safety and loadpoint semantics.
  - Home Assistant remains authoritative for smart-home device integration.
  - EOS remains a pure optimizer.
  - EOS Connect becomes the orchestration layer.
  - MQTT remains useful without becoming the fragile command backbone.

## Validation Notes

Planning ticket only. No code or Nix evaluation required yet.
