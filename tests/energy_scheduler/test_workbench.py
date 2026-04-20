from __future__ import annotations

import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from energy_scheduler.calendar import build_default_calendar, load_or_create_calendar, update_calendar_day
from energy_scheduler.config import RuntimeConfig
from energy_scheduler.workbench import WorkbenchStore


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


class WorkbenchStoreTests(unittest.TestCase):
    def test_create_scenario_clones_live_config_and_embeds_calendar(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            live_calendar = load_or_create_calendar(state_dir, config.assets["tesla"]["recurring_schedule"], persist=True)
            store = WorkbenchStore(state_dir, config, lambda: live_calendar)

            scenario = store.create_scenario()
            simulation_start_at = datetime.fromisoformat(scenario["simulation_start_at"])

            self.assertEqual(scenario["config"]["scheduler"]["bucket_minutes"], 15)
            self.assertEqual(scenario["config"]["scheduler"]["horizon_buckets"], 96)
            self.assertEqual(simulation_start_at.hour, 0)
            self.assertEqual(simulation_start_at.minute, 0)
            self.assertIn("calendar", scenario["config"]["assets"]["tesla"])
            self.assertEqual(
                scenario["config"]["assets"]["tesla"]["calendar"]["days"][0]["date"],
                live_calendar["days"][0]["date"],
            )

    def test_save_scenario_resizes_series_when_horizon_changes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            store = WorkbenchStore(
                state_dir,
                config,
                lambda: build_default_calendar(config.assets["tesla"]["recurring_schedule"]),
            )
            scenario = store.create_scenario()
            scenario["simulation_start_at"] = "2026-04-20T08:00:00+02:00"
            scenario["config"]["scheduler"]["horizon_buckets"] = 12

            saved = store.save_scenario(scenario["id"], scenario)

            self.assertEqual(len(saved["config"]["forecasts"]["prices"]["import_czk_per_kwh"]), 12)
            self.assertEqual(len(saved["config"]["assets"]["battery"]["reserve_target_kwh"]), 12)
            self.assertEqual(len(saved["config"]["assets"]["base_load"]["fixed_demand_kwh"]), 12)

    def test_run_scenario_uses_explicit_start_and_local_tesla_calendar(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            live_calendar = load_or_create_calendar(state_dir, config.assets["tesla"]["recurring_schedule"], persist=True)
            first_day = live_calendar["days"][0]["date"]
            update_calendar_day(
                state_dir,
                config.assets["tesla"]["recurring_schedule"],
                first_day,
                {"mode": "explicit_departure", "departure_time": "09:30", "target_soc_pct": 85},
            )
            store = WorkbenchStore(state_dir, config, lambda: load_or_create_calendar(state_dir, config.assets["tesla"]["recurring_schedule"], persist=True))
            scenario = store.create_scenario()
            scenario["simulation_start_at"] = f"{first_day}T06:00:00+02:00"
            scenario["config"]["assets"]["tesla"]["calendar"]["days"][0] = {
                "date": first_day,
                "mode": "explicit_departure",
                "departure_time": "07:15",
                "target_soc_pct": 70,
                "confidence": 0.9,
                "updated_at": datetime.now().astimezone().isoformat(),
            }
            store.save_scenario(scenario["id"], scenario)

            result = store.run_scenario(scenario["id"])

            self.assertEqual(result["simulation_start_at"], f"{first_day}T06:00:00+02:00")
            self.assertEqual(result["snapshot"]["summary"]["planner_timestamp"], f"{first_day}T06:00:00+02:00")
            self.assertEqual(result["snapshot"]["summary"]["next_tesla_day"]["departure_time"], "07:15")

    def test_run_scenario_handles_export_above_import_prices(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            store = WorkbenchStore(
                state_dir,
                config,
                lambda: build_default_calendar(config.assets["tesla"]["recurring_schedule"]),
            )
            scenario = store.create_scenario()
            scenario["config"]["forecasts"]["prices"]["export_czk_per_kwh"][28:34] = [4.61, 5.44, 5.74, 5.89, 5.83, 4.99]

            store.save_scenario(scenario["id"], scenario)
            result = store.run_scenario(scenario["id"])

            self.assertEqual(result["snapshot"]["summary"]["planner_status"], "ok")

    def test_invalid_demand_window_returns_field_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            store = WorkbenchStore(
                state_dir,
                config,
                lambda: build_default_calendar(config.assets["tesla"]["recurring_schedule"]),
            )
            scenario = store.create_scenario()
            scenario["config"]["assets"]["demands"] = [
                {
                    "asset_id": "boiler",
                    "bands": [
                        {
                            "id": "boiler-required",
                            "display_name": "Boiler minimum heat",
                            "start_index": 0,
                            "deadline_index": 99,
                            "earliest_start_index": 0,
                            "latest_finish_index": 99,
                            "target_quantity_kwh": 4.0,
                            "min_power_kw": 0.0,
                            "max_power_kw": 3.0,
                            "interruptible": True,
                            "preemptible": True,
                            "marginal_value_czk_per_kwh": 3.0,
                            "unmet_penalty_czk_per_kwh": 15.0,
                            "required_level": True,
                            "quantity_unit": "kwh",
                        }
                    ],
                }
            ]

            with self.assertRaises(ValueError) as error:
                store.save_scenario(scenario["id"], scenario)

            self.assertIn("deadline_index", str(error.exception))


if __name__ == "__main__":
    unittest.main()
