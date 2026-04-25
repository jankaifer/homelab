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

## Dashboard UI

An optional separate service exposes the scheduler behind Caddy:

- Domain: `https://energy.frame1.hobitin.eu`
- Binary: `energy-scheduler-ui`
- Runtime: Bun HTTP server with a React client bundle
- Reads planner state from:
  - `/var/lib/energy-scheduler/latest-plan.json`
  - `/var/lib/energy-scheduler/history/*.json`
- Uses shared TypeScript types between the Bun API server and React client
- Shows a single read-only dashboard with:
  - date selection for the whole dashboard
  - headline planner metrics for the selected snapshot
  - future energy forecast from the selected snapshot
  - active demand bands and Tesla planning hints
  - historical planner runs for the selected date
- Does not expose workbench editing, scenario mutation, or Tesla calendar writes

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

Bun UI build and API smoke tests:

```bash
(cd frontend/energy-ui-charts && bun run build)
PYTHONPATH=src ./.venv/bin/python -m unittest tests.energy_scheduler.test_ui_api -v
```

## Next Integrations

Current adapter layer is config-backed. The next steps are device-backed adapters for:

- Victron solar and battery telemetry/control
- Tesla schedule and charging control
- Historical base-load forecasting
- Boiler, pool, and other flexible demand adapters
