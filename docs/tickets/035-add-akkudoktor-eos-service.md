# Ticket 035: Add Akkudoktor-EOS Service

**Status**: DONE
**Created**: 2026-04-26
**Updated**: 2026-05-20

## Task

Add Akkudoktor-EOS as the read-only optimizer API service for the homelab energy stack.

## Implementation Plan

1. Add `modules/services/akkudoktor-eos.nix`.
2. Run EOS as an OCI container, following the existing Home Assistant and Zigbee2MQTT container pattern.
3. Use the upstream `akkudoktor/eos` image with a configurable `image` option so the implementation can pin a tag or digest.
4. Persist EOS data under `/var/lib/akkudoktor-eos`.
5. Expose the EOS API on an internal host-local port, expected to be `8503`.
6. Expose the EOS dashboard/UI on an internal host-local port, expected to be `8504`, if the upstream image provides it.
7. Route EOS through Caddy at `https://eos.frame1.hobitin.eu` and add a Homepage entry.
8. Keep EOS as a pure optimizer service:
   - no direct charger control
   - no direct heat pump control
   - no direct MQTT command publishing in v1
9. Document that EOS Connect is the only planned caller that turns optimizer output into control decisions.
10. During the first rollout, treat EOS output as advisory only: log/display plans but do not apply them to evcc, Home Assistant, MQTT command topics, or physical devices.

Control boundary:

- EOS receives forecasts, prices, constraints, and current state from EOS Connect.
- EOS returns an optimization plan.
- EOS does not command evcc, Home Assistant, MQTT, or physical devices directly.
- No other service may apply EOS plans automatically during the first rollout.

## Work Log

### 2026-04-26

- Created ticket from the hybrid integration decision in Ticket 033.
- Confirmed EOS belongs in the stack as an optimizer API, not as the orchestration layer.
- Marked the first EOS rollout as advisory/read-only.
- Deferred applying optimizer output to any real device until a later active-control ticket.
- Added `modules/services/akkudoktor-eos.nix` as an OCI container module.
- Configured the upstream `akkudoktor/eos` image with persistent `/data`, host-local API port `8503`, and host-local dashboard port `8504`.
- Routed the dashboard through Caddy at `https://eos.frame1.hobitin.eu` and added a Homepage entry.
- Documented the service in `docs/services/akkudoktor-eos.md`.

### 2026-05-20

- Reproduced the EOSdash `Plan` click failure: `GET /eosdash/plan?dark=false` returned HTTP 500 while `Prediction` returned HTTP 200.
- Live logs showed EOS could serve optimization requests but failed to write `/data/measurement.json` and `/data/cache` after dropping to the in-container `eos` user.
- Updated the service module so `/var/lib/akkudoktor-eos` is owned by the EOS container UID/GID (`100:101`) instead of `root:root`.
- Confirmed a second Plan failure after fresh optimizer results: EOS had no prediction providers enabled, `/v1/prediction/keys` returned `[]`, and the Plan dashboard crashed while plotting a solution whose prediction dataframe only contained `date_time`.
- Added module support for a declarative `/data/config/EOS.config.json` and configured `frame1` with advisory prediction providers for Prague-area PV/weather/load/electricity-price data.
- Adjusted the placeholder PV plane azimuth from exact south (`180`) to `179` degrees. EOS translates exact south to Akkudoktor API `azimuth=0`, which the upstream forecast API rejects with HTTP 400; `179` preserves the intended orientation while allowing dynamic PV forecast requests to succeed.

## Validation Notes

Validation completed:

- `nix fmt`
- `nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'`
- `./scripts/run-vm-docker.sh --build`
- Deployed with `nix run .#deploy -- .#frame1 --skip-checks`
- Verified `podman-akkudoktor-eos.service` active
- Verified EOS logs show the API on `0.0.0.0:8503` and EOSdash on `0.0.0.0:8504`
- Verified `https://eos.frame1.hobitin.eu` returns HTTP 200
- Verified Homepage contains the `Akkudoktor EOS` link
