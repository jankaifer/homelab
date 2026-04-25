from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from energy_scheduler.config import RuntimeConfig
from energy_scheduler.ui import UIServer


def _build_config(state_dir: Path) -> RuntimeConfig:
    return RuntimeConfig(
        raw={
            "scheduler": {
                "bucket_minutes": 15,
                "horizon_buckets": 48,
                "loop_interval_seconds": 60,
                "churn_penalty_czk_per_kw_change": 0.01,
            },
            "runtime": {
                "state_dir": str(state_dir),
                "grid_available": True,
            },
            "forecasts": {
                "prices": {
                    "import_czk_per_kwh": [4.5] * 48,
                    "export_czk_per_kwh": [1.0] * 48,
                },
                "solar": {
                    "asset_id": "solar-main",
                    "export_allowed": True,
                    "curtailment_allowed": True,
                    "scenarios": [
                        {"id": "solar-low", "probability": 0.2, "generation_kwh": [0.0] * 48, "labels": {"kind": "low"}},
                        {"id": "solar-expected", "probability": 0.6, "generation_kwh": [0.0] * 48, "labels": {"kind": "expected"}},
                        {"id": "solar-high", "probability": 0.2, "generation_kwh": [0.0] * 48, "labels": {"kind": "high"}},
                    ],
                },
            },
            "assets": {
                "battery": {
                    "asset_id": "home-battery",
                    "capacity_kwh": 10.0,
                    "initial_soc_kwh": 5.0,
                    "min_soc_kwh": 1.0,
                    "max_soc_kwh": 10.0,
                    "max_charge_kw": 4.0,
                    "max_discharge_kw": 4.0,
                    "charge_efficiency": 0.95,
                    "discharge_efficiency": 0.95,
                    "cycle_cost_czk_per_kwh": 0.15,
                    "grid_charge_allowed": True,
                    "export_discharge_allowed": True,
                    "emergency_floor_kwh": 1.5,
                    "reserve_target_kwh": [3.0] * 48,
                    "reserve_value_czk_per_kwh": [0.02] * 48,
                },
                "tesla": {
                    "asset_id": "tesla-model-3",
                    "battery_capacity_kwh": 57.5,
                    "current_soc_pct": 40.0,
                    "default_start_soc_pct": 20.0,
                    "charge_power_kw": 11.0,
                    "required_marginal_value_czk_per_kwh": 5.0,
                    "required_unmet_penalty_czk_per_kwh": 30.0,
                    "opportunistic_target_soc_pct": 80.0,
                    "opportunistic_marginal_value_czk_per_kwh": 2.0,
                    "recurring_schedule": [
                        {"weekday": 0, "departure_time": "07:00", "target_soc_pct": 60.0, "confidence": 0.35},
                        {"weekday": 1, "departure_time": "07:00", "target_soc_pct": 60.0, "confidence": 0.35},
                    ],
                },
                "base_load": {
                    "fixed_demand_kwh": [0.4] * 48,
                },
                "demands": [],
            },
        },
        path=state_dir / "config.json",
    )


class UiApiTests(unittest.TestCase):
    def test_dashboard_uses_latest_plan_for_selected_date(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            ui = UIServer(config)
            snapshot = ui.scheduler.run_once(persist=False, start_at=datetime.fromisoformat("2026-04-20T08:00:00+02:00"))
            state_dir.mkdir(exist_ok=True)
            (state_dir / "latest-plan.json").write_text(json.dumps(snapshot), encoding="utf-8")

            dashboard = ui.dashboard("2026-04-20")

            self.assertEqual(dashboard["selected_date"], "2026-04-20")
            self.assertEqual(dashboard["selected_plan"]["summary"]["planner_timestamp"], "2026-04-20T08:00:00+02:00")
            self.assertEqual(dashboard["history"], [])
            self.assertIn("2026-04-20", dashboard["available_dates"])

    def test_dashboard_lists_history_for_selected_date(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            ui = UIServer(config)
            state_dir.mkdir(exist_ok=True)
            history_dir = state_dir / "history"
            history_dir.mkdir()

            first = ui.scheduler.run_once(persist=False, start_at=datetime.fromisoformat("2026-04-20T08:00:00+02:00"))
            second = ui.scheduler.run_once(persist=False, start_at=datetime.fromisoformat("2026-04-20T09:00:00+02:00"))
            other = ui.scheduler.run_once(persist=False, start_at=datetime.fromisoformat("2026-04-21T08:00:00+02:00"))
            (state_dir / "latest-plan.json").write_text(json.dumps(other), encoding="utf-8")
            (history_dir / "20260420T080000+0200.json").write_text(json.dumps(first), encoding="utf-8")
            (history_dir / "20260420T090000+0200.json").write_text(json.dumps(second), encoding="utf-8")

            dashboard = ui.dashboard("2026-04-20")

            self.assertEqual(len(dashboard["history"]), 2)
            self.assertEqual(dashboard["history"][0]["created_at"], "2026-04-20T09:00:00+02:00")
            self.assertEqual(dashboard["selected_plan"]["summary"]["planner_timestamp"], "2026-04-20T09:00:00+02:00")


if __name__ == "__main__":
    unittest.main()
