from __future__ import annotations

import unittest
from datetime import datetime, timezone

from energy_scheduler.domain import BatteryState, DemandBand, DemandPlanInput, DemandUnit, PlannerInput, PriceSeries, ProducerForecast, Scenario
from energy_scheduler.planner.optimizer import solve_plan


class OptimizerTests(unittest.TestCase):
    def _build_input(self, *, export_price: float = 1.0, import_price: float = 2.0, grid_available: bool = True) -> PlannerInput:
        horizon = 8
        prices = PriceSeries(
            import_prices=[import_price] * horizon,
            export_prices=[export_price] * horizon,
        )
        producer = ProducerForecast(
            asset_id="solar",
            scenarios=[
                Scenario("low::departure", 0.25, [0.0, 0.0, 2.0, 2.0, 0.0, 0.0, 0.0, 0.0]),
                Scenario("high::departure", 0.25, [0.0, 0.0, 4.0, 4.0, 0.0, 0.0, 0.0, 0.0]),
                Scenario("low::home", 0.25, [0.0, 0.0, 2.0, 2.0, 0.0, 0.0, 0.0, 0.0]),
                Scenario("high::home", 0.25, [0.0, 0.0, 4.0, 4.0, 0.0, 0.0, 0.0, 0.0]),
            ],
        )
        battery = BatteryState(
            asset_id="battery",
            capacity_kwh=12.0,
            initial_soc_kwh=4.0,
            min_soc_kwh=1.0,
            max_soc_kwh=12.0,
            max_charge_kw=4.0,
            max_discharge_kw=4.0,
            charge_efficiency=0.95,
            discharge_efficiency=0.95,
            cycle_cost_czk_per_kwh=0.05,
            grid_charge_allowed=True,
            export_discharge_allowed=True,
            emergency_floor_kwh=1.0,
            reserve_target_kwh=[1.0] * horizon,
            reserve_value_czk_per_kwh=[0.0] * horizon,
        )
        demand = DemandPlanInput(
            fixed_demand_kwh=[0.2] * horizon,
            demand_bands=[
                DemandBand(
                    band_id="tesla-required:departure",
                    asset_id="tesla",
                    start_index=0,
                    deadline_index=6,
                    earliest_start_index=0,
                    latest_finish_index=6,
                    target_quantity_kwh=3.0,
                    min_power_kw=0.0,
                    max_power_kw=3.0,
                    interruptible=True,
                    preemptible=True,
                    marginal_value_czk_per_kwh=5.0,
                    unmet_penalty_czk_per_kwh=30.0,
                    required_level=True,
                    quantity_unit=DemandUnit.KWH,
                    scenario_id="low::departure",
                ),
                DemandBand(
                    band_id="tesla-required:departure@high",
                    asset_id="tesla",
                    start_index=0,
                    deadline_index=6,
                    earliest_start_index=0,
                    latest_finish_index=6,
                    target_quantity_kwh=3.0,
                    min_power_kw=0.0,
                    max_power_kw=3.0,
                    interruptible=True,
                    preemptible=True,
                    marginal_value_czk_per_kwh=5.0,
                    unmet_penalty_czk_per_kwh=30.0,
                    required_level=True,
                    quantity_unit=DemandUnit.KWH,
                    scenario_id="high::departure",
                ),
                DemandBand(
                    band_id="tesla-extra",
                    asset_id="tesla",
                    start_index=0,
                    deadline_index=7,
                    earliest_start_index=0,
                    latest_finish_index=7,
                    target_quantity_kwh=2.0,
                    min_power_kw=0.0,
                    max_power_kw=3.0,
                    interruptible=True,
                    preemptible=True,
                    marginal_value_czk_per_kwh=1.5,
                    unmet_penalty_czk_per_kwh=0.0,
                    required_level=False,
                    quantity_unit=DemandUnit.KWH,
                    scenario_id=None,
                ),
                DemandBand(
                    band_id="pool-extra",
                    asset_id="pool",
                    start_index=2,
                    deadline_index=7,
                    earliest_start_index=2,
                    latest_finish_index=7,
                    target_quantity_kwh=4.0,
                    min_power_kw=0.0,
                    max_power_kw=4.0,
                    interruptible=True,
                    preemptible=True,
                    marginal_value_czk_per_kwh=0.2,
                    unmet_penalty_czk_per_kwh=0.0,
                    required_level=False,
                    quantity_unit=DemandUnit.KWH,
                    scenario_id=None,
                ),
            ],
        )
        return PlannerInput(
            created_at=datetime.now(timezone.utc),
            bucket_minutes=60,
            horizon_buckets=horizon,
            prices=prices,
            producer=producer,
            battery=battery,
            demand=demand,
            grid_available=grid_available,
        )

    def test_required_tesla_band_is_satisfied_when_feasible(self) -> None:
        result = solve_plan(self._build_input())
        shortfalls = {
            (item.band_id, item.scenario_id): item.unmet_kwh
            for item in result.shortfalls
        }
        self.assertAlmostEqual(shortfalls[("tesla-required:departure", "low::departure")], 0.0, places=4)
        self.assertAlmostEqual(shortfalls[("tesla-required:departure@high", "high::departure")], 0.0, places=4)

    def test_low_value_pool_yields_to_export(self) -> None:
        result = solve_plan(self._build_input(export_price=1.0))
        served_pool = sum(item.served_kwh for item in result.band_allocations if item.band_id == "pool-extra")
        exported = sum(item.export_kwh for item in result.battery_plan if item.scenario_id == "high::home")
        self.assertLess(served_pool, 1.0)
        self.assertGreater(exported, 1.0)

    def test_outage_disables_grid_import(self) -> None:
        result = solve_plan(self._build_input(grid_available=False))
        imported = sum(item.import_kwh for item in result.battery_plan)
        self.assertAlmostEqual(imported, 0.0, places=6)


if __name__ == "__main__":
    unittest.main()
