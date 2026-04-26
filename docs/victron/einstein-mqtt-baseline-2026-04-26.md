# Victron Einstein MQTT Baseline

**Captured:** 2026-04-26T18:09:31.029888+00:00
**Finished:** 2026-04-26T18:10:46.355743+00:00
**Host:** `192.168.2.31`
**MQTT:** TLS on `8883` with self-signed `venus.local` certificate
**Portal ID:** `c0619ab82091`
**Password source:** `secrets/victron-einstein-mqtt-password.age`
**Topics captured:** 2011

## Capture Method

- Subscribed to `N/#` and `$SYS/#`.
- Published `R/c0619ab82091/keepalive` 4 times for `Victron MQTT telemetry keepalive request`.
- No device-control, setpoint, charger-control, or configuration topics were published.
- Raw latest topic payloads are stored in the companion JSON file.

## Service Summary

| Service | Instance | Topics |
|---------|----------|--------|
| `$SYS` | `broker` | 32 |
| `N` | `` | 2 |
| `adc` | `0` | 16 |
| `battery` | `512` | 92 |
| `digitalinputs` | `0` | 8 |
| `evcharger` | `40` | 28 |
| `fronius` | `0` | 2 |
| `hub4` | `0` | 12 |
| `logger` | `0` | 9 |
| `modbusclient` | `0` | 5 |
| `modbustcp` | `0` | 27 |
| `platform` | `0` | 132 |
| `settings` | `0` | 819 |
| `solarcharger` | `0` | 128 |
| `system` | `0` | 212 |
| `temperature` | `20` | 16 |
| `vebus` | `276` | 445 |
| `vecan` | `vecan0` | 26 |

## Notable Current Values

- `N/c0619ab82091/system/0/Serial`: `{"value":"c0619ab82091"}`
- `N/c0619ab82091/system/0/Dc/Battery/Power`: `{"value":-74}`
- `N/c0619ab82091/system/0/Dc/Battery/Voltage`: `{"value":49.86000061035156}`
- `N/c0619ab82091/system/0/Dc/Battery/Current`: `{"value":-1.5}`
- `N/c0619ab82091/system/0/Dc/Pv/Power`: `{"value":39.92800047290325}`
- `N/c0619ab82091/system/0/Ac/Grid/L1/Power`: `{"value":679}`
- `N/c0619ab82091/system/0/Ac/Grid/L2/Power`: `{"value":381}`
- `N/c0619ab82091/system/0/Ac/Grid/L3/Power`: `{"value":697}`
- `N/c0619ab82091/vebus/276/Ac/ActiveIn/P`: `{"value":1757}`
- `N/c0619ab82091/battery/512/Dc/0/Power`: `{"value":-99}`
- `N/c0619ab82091/evcharger/40/Status`: `{"value":0}`

## Baseline Files

- JSON baseline: `docs/victron/einstein-mqtt-baseline-2026-04-26.json`
- Markdown summary: `docs/victron/einstein-mqtt-baseline-2026-04-26.md`
