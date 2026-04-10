from __future__ import annotations

import json
import time
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from energy_scheduler.adapters.config import ConfigBatteryAdapter, ConfigDemandAdapter, ConfigPriceAdapter, ConfigSolarAdapter, validate_scenario_coverage
from energy_scheduler.config import RuntimeConfig
from energy_scheduler.domain import PlannerInput
from energy_scheduler.planner.optimizer import solve_plan


class SchedulerService:
    def __init__(self, config: RuntimeConfig):
        self.config = config
        validate_scenario_coverage(config)
        self.state_dir = Path(config.runtime.get("state_dir", "/var/lib/energy-scheduler"))
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.history_dir = self.state_dir / "history"
        self.history_dir.mkdir(exist_ok=True)
        self.price_adapter = ConfigPriceAdapter(config)
        self.solar_adapter = ConfigSolarAdapter(config)
        self.battery_adapter = ConfigBatteryAdapter(config)
        self.demand_adapter = ConfigDemandAdapter(config)

    @property
    def bucket_minutes(self) -> int:
        return int(self.config.scheduler.get("bucket_minutes", 15))

    @property
    def horizon_buckets(self) -> int:
        return int(self.config.scheduler.get("horizon_buckets", 192))

    def build_input(self) -> PlannerInput:
        now = datetime.now(timezone.utc)
        prices = self.price_adapter.get_prices(self.horizon_buckets)
        producer = self.solar_adapter.get_forecast(self.horizon_buckets)
        producer = self._expand_joint_scenarios(producer)
        battery = self.battery_adapter.get_battery(self.horizon_buckets)
        demand = self.demand_adapter.get_demand(self.horizon_buckets, self.bucket_minutes)
        demand = self._expand_demand_scenarios(demand, [scenario.scenario_id for scenario in producer.scenarios])
        grid_available = bool(self.config.runtime.get("grid_available", True))
        return PlannerInput(
            created_at=now,
            bucket_minutes=self.bucket_minutes,
            horizon_buckets=self.horizon_buckets,
            prices=prices,
            producer=producer,
            battery=battery,
            demand=demand,
            grid_available=grid_available,
            churn_penalty_czk_per_kw_change=float(self.config.scheduler.get("churn_penalty_czk_per_kw_change", 0.0)),
            previous_battery_target_kw=float(self.config.runtime.get("previous_battery_target_kw", 0.0)),
        )

    def _expand_joint_scenarios(self, producer):
        demand_scenarios = self.config.assets.get("scenario_weights", {})
        if not demand_scenarios:
            return producer

        joint_scenarios = []
        total_probability = 0.0
        for solar in producer.scenarios:
            for demand_id, weight in demand_scenarios.items():
                probability = solar.probability * float(weight)
                joint_scenarios.append(
                    type(solar)(
                        scenario_id=f"{solar.scenario_id}::{demand_id}",
                        probability=probability,
                        solar_generation_kwh=solar.solar_generation_kwh,
                        labels={**solar.labels, "demand_scenario": demand_id},
                    )
                )
                total_probability += probability

        if total_probability <= 0:
            raise ValueError("joint scenario probabilities must be positive")

        normalized = []
        for scenario in joint_scenarios:
            normalized.append(
                type(scenario)(
                    scenario_id=scenario.scenario_id,
                    probability=scenario.probability / total_probability,
                    solar_generation_kwh=scenario.solar_generation_kwh,
                    labels=scenario.labels,
                )
            )
        producer.scenarios = normalized
        return producer

    def _expand_demand_scenarios(self, demand, joint_scenario_ids: list[str]):
        expanded = []
        for band in demand.demand_bands:
            if band.scenario_id is None:
                expanded.append(band)
                continue
            matching_joint_ids = [
                scenario_id for scenario_id in joint_scenario_ids
                if scenario_id.endswith(f"::{band.scenario_id}")
            ]
            if not matching_joint_ids:
                raise ValueError(f"no joint scenarios found for demand scenario '{band.scenario_id}'")
            for joint_id in matching_joint_ids:
                clone = type(band)(**{
                    **band.__dict__,
                    "band_id": f"{band.band_id}@{joint_id}",
                    "scenario_id": joint_id,
                })
                expanded.append(clone)
        demand.demand_bands = expanded
        return demand

    def run_once(self) -> dict[str, object]:
        plan_input = self.build_input()
        result = solve_plan(plan_input)
        snapshot = {
            "created_at": plan_input.created_at.isoformat(),
            "objective_value_czk": result.objective_value_czk,
            "summary": result.summary,
            "shortfalls": [asdict(item) for item in result.shortfalls],
            "battery_plan": [asdict(item) for item in result.battery_plan[: min(24, len(result.battery_plan))]],
            "band_allocations": [asdict(item) for item in result.band_allocations[:200]],
        }
        latest = self.state_dir / "latest-plan.json"
        latest.write_text(json.dumps(snapshot, indent=2, sort_keys=True), encoding="utf-8")
        history_path = self.history_dir / f"{plan_input.created_at.strftime('%Y%m%dT%H%M%SZ')}.json"
        history_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True), encoding="utf-8")
        return snapshot

    def serve_forever(self) -> None:
        interval_s = int(self.config.scheduler.get("loop_interval_seconds", 60))
        while True:
            self.run_once()
            time.sleep(interval_s)
