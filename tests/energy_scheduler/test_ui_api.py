from __future__ import annotations

import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path

from energy_scheduler.config import RuntimeConfig
from energy_scheduler.ui import UIRequestHandler, UIServer
from http.server import ThreadingHTTPServer


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
            httpd = ThreadingHTTPServer(("127.0.0.1", 0), UIRequestHandler)
            httpd.ui_server = ui  # type: ignore[attr-defined]
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            try:
                conn = http.client.HTTPConnection("127.0.0.1", httpd.server_port)
                conn.request("GET", "/api/tesla/calendar")
                response = conn.getresponse()
                payload = json.loads(response.read())
                self.assertEqual(response.status, 200)
                first_day = payload["days"][0]["date"]

                conn.request(
                    "PUT",
                    f"/api/tesla/calendar/{first_day}",
                    body=json.dumps({"mode": "explicit_departure", "departure_time": "06:30", "target_soc_pct": 70}),
                    headers={"Content-Type": "application/json"},
                )
                update_response = conn.getresponse()
                updated = json.loads(update_response.read())
                self.assertEqual(update_response.status, 200)
                day = next(item for item in updated["days"] if item["date"] == first_day)
                self.assertEqual(day["mode"], "explicit_departure")
                self.assertAlmostEqual(day["confidence"], 0.9, places=6)

                conn.request("GET", "/api/live/plan")
                plan_response = conn.getresponse()
                plan = json.loads(plan_response.read())
                self.assertEqual(plan_response.status, 200)
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
            finally:
                httpd.shutdown()
                httpd.server_close()
                thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
