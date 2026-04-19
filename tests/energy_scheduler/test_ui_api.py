from __future__ import annotations

import tempfile
import unittest
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
    def test_calendar_get_and_put(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            ui = UIServer(config)
            payload = ui.get_calendar()
            first_day = payload["days"][0]["date"]

            updated = ui.update_calendar(
                first_day,
                {"mode": "explicit_departure", "departure_time": "06:30", "target_soc_pct": 70},
            )
            day = next(item for item in updated["days"] if item["date"] == first_day)
            self.assertEqual(day["mode"], "explicit_departure")
            self.assertAlmostEqual(day["confidence"], 0.9, places=6)

            plan = ui.plan_for_scenario("real")
            tesla_required = [
                band for band in plan["bands"]
                if band["asset_id"] == "tesla-model-3" and band["required_level"]
            ]
            logical_keys = {
                (
                    band["display_name"],
                    band.get("metadata", {}).get("date"),
                    band.get("metadata", {}).get("departure_time"),
                )
                for band in tesla_required
            }
            self.assertEqual(len(tesla_required), len(logical_keys))

    def test_scenarios_endpoint_and_fake_plan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            ui = UIServer(config)
            payload = ui.scenarios()
            scenario_ids = [scenario["id"] for scenario in payload["scenarios"]]
            self.assertEqual(scenario_ids, ["real", "winter", "spring", "summer", "autumn"])

            winter_plan = ui.plan_for_scenario("winter")
            self.assertEqual(winter_plan["selected_scenario"]["id"], "winter")
            self.assertEqual(winter_plan["summary"]["scenario_kind"], "fake")
            self.assertTrue(winter_plan["summary"]["scenario_read_only"])

            real_plan = ui.plan_for_scenario("real")
            self.assertEqual(real_plan["selected_scenario"]["id"], "real")
            self.assertEqual(real_plan["summary"]["scenario_kind"], "real")
            self.assertFalse(real_plan["summary"]["scenario_read_only"])

    def test_workbench_crud_and_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            config = _build_config(state_dir)
            ui = UIServer(config)

            created = ui.create_workbench_scenario()
            self.assertTrue(created["id"].startswith("scenario-"))

            listed = ui.list_workbench_scenarios()["scenarios"]
            self.assertEqual(len(listed), 1)
            self.assertEqual(listed[0]["id"], created["id"])

            created["name"] = "Planner stress test"
            created["simulation_start_at"] = "2026-04-20T08:00:00+02:00"
            created["config"]["scheduler"]["horizon_buckets"] = 24
            saved = ui.save_workbench_scenario(created["id"], created)
            self.assertEqual(saved["name"], "Planner stress test")
            self.assertEqual(len(saved["config"]["forecasts"]["prices"]["import_czk_per_kwh"]), 24)

            clone = ui.clone_workbench_scenario(created["id"])
            self.assertNotEqual(clone["id"], created["id"])

            result = ui.run_workbench_scenario(created["id"])
            self.assertEqual(result["scenario_id"], created["id"])
            self.assertEqual(result["snapshot"]["summary"]["planner_timestamp"], "2026-04-20T08:00:00+02:00")

            fetched_result = ui.get_workbench_result(created["id"])
            self.assertEqual(fetched_result["run_at"], result["run_at"])


if __name__ == "__main__":
    unittest.main()
