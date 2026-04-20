# Energy Scheduler

Local-first energy scheduling daemon for solar production, battery storage, and flexible demand orchestration.

## Status

**Enabled:** No

## Configuration

**Module:** `modules/services/energy-scheduler.nix`  
**Pattern:** `homelab.services.energyScheduler.enable`

### Key options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `homelab.services.energyScheduler.enable` | bool | false | Enable the scheduler systemd service |
| `homelab.services.energyScheduler.package` | package | repo-local package | Python application package |
| `homelab.services.energyScheduler.stateDir` | string | `/var/lib/energy-scheduler` | Runtime state, plans, and history |
| `homelab.services.energyScheduler.settings` | JSON attrset | see module | Planner horizon, scenarios, prices, battery, and demand bands |

## Runtime Model

- Long-running Python daemon under `systemd`
- Re-solves the horizon every 60 seconds by default
- Uses 15-minute buckets over a multi-day horizon by default
- Writes latest plan and timestamped plan history into `/var/lib/energy-scheduler`
- Seeds and reads a shared Tesla 14-day planning calendar at `/var/lib/energy-scheduler/tesla-calendar.json`

## Explainability UI

An optional separate service exposes the scheduler behind Caddy:

- Domain: `https://energy.frame1.hobitin.eu`
- Binary: `energy-scheduler-ui`
- Reads planner state from `/var/lib/energy-scheduler/latest-plan.json`
- Shows four pages:
  - `Overview` for the current plan headline, summary cards, and deduplicated demand bands
  - `Timeline` for a 24-hour energy-balance chart and battery SoC chart
  - `Tesla Plan` for the Tesla charging chart and the 14-day planning calendar
  - `Workbench` for local named scenario editing, simulation, and result inspection
- Includes a source switcher with one `Real-time` plan and four prepared seasonal demos: `Winter`, `Spring`, `Summer`, and `Autumn`
- Fake seasonal demos reuse the live Tesla planning hints but make the Tesla calendar read-only to avoid mutating real runtime state while previewing synthetic data
- Lets you update Tesla departure planning for the next 14 days through a calendar day modal
- Rolls the Tesla planning window forward automatically so the calendar always covers the next 14 days
- Stores workbench scenarios and run results under the shared state directory:
  - `/var/lib/energy-scheduler/workbench/scenarios/*.json`
  - `/var/lib/energy-scheduler/workbench/results/*.json`
  - `/var/lib/energy-scheduler/workbench/runtime/<scenario-id>/`
- Clones the live planner config when you create a new scenario, but keeps Tesla calendar overrides and all edits scenario-local after that
- Seeds a fresh workbench with a single default scenario covering the current day from local midnight over 24 hours
- Supports typed editors for prices, solar scenarios, battery settings, base load, Tesla schedule/calendar, and generic demand bands
- Runs the same planner core on demand with an explicit simulation start time instead of using wall-clock `now`

## Planner Model

The scheduler models:

- `Producer` for forecast generation, currently solar scenarios
- `Battery` as a dedicated time-coupled storage model
- `Demand` as stacked value bands with per-band windows and CZK-per-kWh value

Key assumptions:

- Import and export are both modeled as bucketed market prices
- The grid is treated as a single net connection in arbitrage-prone buckets, so the planner will not exploit simultaneous import/export loops
- Explicit uncertainty is carried only for solar and future car-need scenarios in v1
- Infeasible plans still emit the least-bad result plus shortfalls
- Outage handling uses the same optimizer with import removed as an available source

## Files

- Generated config: store path generated from `homelab.services.energyScheduler.settings`
- State directory: `/var/lib/energy-scheduler`
- Latest plan: `/var/lib/energy-scheduler/latest-plan.json`
- Plan history: `/var/lib/energy-scheduler/history/*.json`
- Tesla calendar: `/var/lib/energy-scheduler/tesla-calendar.json`
- Workbench scenarios: `/var/lib/energy-scheduler/workbench/scenarios/*.json`
- Workbench results: `/var/lib/energy-scheduler/workbench/results/*.json`

## Example

```nix
homelab.services.energyScheduler = {
  enable = true;
  settings.assets.battery.initial_soc_kwh = 6.5;
  settings.forecasts.prices.import_czk_per_kwh = builtins.genList (_: 4.8) 192;
};
```

## Validation

Build evaluation:

```bash
nix eval .#nixosConfigurations.frame1-vm.config.system.build.toplevel --apply 'x: x.drvPath'
```

One-shot planner run after enabling:

```bash
sudo systemctl start energy-scheduler.service
sudo journalctl -u energy-scheduler -n 200 --no-pager
sudo cat /var/lib/energy-scheduler/latest-plan.json
```

Browser regression pass against a local demo:

```bash
./scripts/run-energy-ui-demo.sh --port 8790
./scripts/check-energy-ui-browser.sh --url http://127.0.0.1:8790/
```

Workbench API smoke test in the dev shell:

```bash
PYTHONPATH=src ./.venv/bin/python -m unittest tests.energy_scheduler.test_workbench tests.energy_scheduler.test_ui_api -v
```

## Next Integrations

Current adapter layer is config-backed. The next steps are device-backed adapters for:

- Victron solar and battery telemetry/control
- Tesla schedule and charging control
- Historical base-load forecasting
- Boiler, pool, and other flexible demand adapters
