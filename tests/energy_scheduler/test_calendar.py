from __future__ import annotations

import tempfile
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

from energy_scheduler.calendar import build_default_calendar, build_tesla_scenarios, load_or_create_calendar, update_calendar_day


class TeslaCalendarTests(unittest.TestCase):
    def setUp(self) -> None:
        self.recurring = [
            {"weekday": weekday, "departure_time": "07:00", "target_soc_pct": 60.0, "confidence": 0.35}
            for weekday in range(7)
        ]
        self.monday = date(2026, 4, 13)

    def test_default_calendar_uses_low_confidence_departure(self) -> None:
        calendar = build_default_calendar(self.recurring, days=2, today=self.monday)
        self.assertEqual(len(calendar["days"]), 2)
        self.assertAlmostEqual(calendar["days"][0]["confidence"], 0.35, places=6)

    def test_explicit_departure_is_90_percent_confidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            calendar = load_or_create_calendar(state_dir, self.recurring, persist=True)
            day_date = calendar["days"][0]["date"]
            updated = update_calendar_day(
                state_dir,
                self.recurring,
                day_date,
                {"mode": "explicit_departure", "departure_time": "06:45", "target_soc_pct": 72},
            )
            day = next(item for item in updated["days"] if item["date"] == day_date)
            self.assertEqual(day["mode"], "explicit_departure")
            self.assertAlmostEqual(day["confidence"], 0.9, places=6)

    def test_no_departure_keeps_ten_percent_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            calendar = load_or_create_calendar(state_dir, self.recurring, persist=True)
            day_date = calendar["days"][0]["date"]
            updated = update_calendar_day(state_dir, self.recurring, day_date, {"mode": "no_departure"})
            day = next(item for item in updated["days"] if item["date"] == day_date)
            self.assertEqual(day["mode"], "no_departure")
            self.assertAlmostEqual(day["confidence"], 0.1, places=6)

    def test_scenarios_include_departure_and_home_outcomes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            state_dir = Path(tmp)
            calendar = load_or_create_calendar(state_dir, self.recurring, persist=True)
            scenario_weights, scenario_labels, _ = build_tesla_scenarios(
                calendar=calendar,
                start_at=datetime.now(timezone.utc),
                horizon_buckets=96,
                bucket_minutes=15,
            )
            self.assertTrue(any("departure" in key for key in scenario_weights))
            self.assertTrue(any("home" in key for key in scenario_weights))
            self.assertAlmostEqual(sum(scenario_weights.values()), 1.0, places=6)
            self.assertEqual(set(scenario_weights), set(scenario_labels))


if __name__ == "__main__":
    unittest.main()
