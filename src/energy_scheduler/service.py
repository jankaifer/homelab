from __future__ import annotations

import json
import time
from collections import defaultdict
from dataclasses import asdict
from datetime import datetime, time
from pathlib import Path
from typing import Any

from energy_scheduler.calendar import load_or_create_calendar
from energy_scheduler.adapters.config import ConfigBatteryAdapter, ConfigDemandAdapter, ConfigPriceAdapter, ConfigSolarAdapter, validate_scenario_coverage
from energy_scheduler.config import RuntimeConfig
from energy_scheduler.domain import PlannerInput, PlannerResult
from energy_scheduler.files import write_json_atomic
from energy_scheduler.planner.optimizer import solve_plan


class SchedulerService:
    def __init__(self, config: RuntimeConfig, persist_runtime_state: bool = True):
        self.config = config
        self.persist_runtime_state = persist_runtime_state
        validate_scenario_coverage(config)
        self.state_dir = Path(config.runtime.get("state_dir", "/var/lib/energy-scheduler"))
        if self.persist_runtime_state:
            self.state_dir.mkdir(parents=True, exist_ok=True)
        self.history_dir = self.state_dir / "history"
        if self.persist_runtime_state:
            self.history_dir.mkdir(exist_ok=True)
        self.price_adapter = ConfigPriceAdapter(config)
        self.solar_adapter = ConfigSolarAdapter(config)
        self.battery_adapter = ConfigBatteryAdapter(config)
        self.demand_adapter = ConfigDemandAdapter(config, persist_runtime_state=self.persist_runtime_state)
        self._ensure_tesla_calendar()

    @property
    def bucket_minutes(self) -> int:
        return int(self.config.scheduler.get("bucket_minutes", 15))

    @property
    def horizon_buckets(self) -> int:
        return int(self.config.scheduler.get("horizon_buckets", 192))

    def _ensure_tesla_calendar(self) -> None:
        tesla = self.config.assets.get("tesla")
        if tesla is None:
            return
        load_or_create_calendar(
            state_dir=self.state_dir,
            recurring_schedule=tesla.get("recurring_schedule", []),
            persist=self.persist_runtime_state,
        )

    def build_input(self) -> PlannerInput:
        now = datetime.now().astimezone()
        prices = self.price_adapter.get_prices(self.horizon_buckets)
        producer = self.solar_adapter.get_forecast(self.horizon_buckets)
        battery = self.battery_adapter.get_battery(self.horizon_buckets)
        demand = self.demand_adapter.get_demand(self.horizon_buckets, self.bucket_minutes, now)
        producer = self._expand_joint_scenarios(producer, demand.scenario_weights, demand.scenario_labels)
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

    def _expand_joint_scenarios(self, producer, demand_scenarios: dict[str, float], demand_labels: dict[str, dict[str, str]]):
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
                        labels={**solar.labels, **demand_labels.get(demand_id, {}), "demand_scenario": demand_id},
                    )
                )
                total_probability += probability
        if total_probability <= 0:
            raise ValueError("joint scenario probabilities must be positive")
        producer.scenarios = [
            type(scenario)(
                scenario_id=scenario.scenario_id,
                probability=scenario.probability / total_probability,
                solar_generation_kwh=scenario.solar_generation_kwh,
                labels=scenario.labels,
            )
            for scenario in joint_scenarios
        ]
        return producer

    def _expand_demand_scenarios(self, demand, joint_scenario_ids: list[str]):
        expanded = []
        for band in demand.demand_bands:
            if band.scenario_id is None:
                expanded.append(band)
                continue
            matching_joint_ids = [scenario_id for scenario_id in joint_scenario_ids if scenario_id.endswith(f"::{band.scenario_id}")]
            if not matching_joint_ids:
                raise ValueError(f"no joint scenarios found for demand scenario '{band.scenario_id}'")
            for joint_id in matching_joint_ids:
                logical_band_id = band.logical_band_id or band.band_id
                clone = type(band)(**{
                    **band.__dict__,
                    "band_id": f"{band.band_id}@{joint_id}",
                    "logical_band_id": logical_band_id,
                    "scenario_id": joint_id,
                })
                expanded.append(clone)
        demand.demand_bands = expanded
        return demand

    def run_once(self, persist: bool | None = None) -> dict[str, object]:
        if persist is None:
            persist = self.persist_runtime_state
        plan_input = self.build_input()
        result = solve_plan(plan_input)
        snapshot = self._build_snapshot(plan_input, result)
        if persist:
            latest = self.state_dir / "latest-plan.json"
            write_json_atomic(latest, snapshot)
            history_path = self.history_dir / f"{plan_input.created_at.strftime('%Y%m%dT%H%M%S%z')}.json"
            write_json_atomic(history_path, snapshot)
        return snapshot

    def serve_forever(self) -> None:
        interval_s = int(self.config.scheduler.get("loop_interval_seconds", 60))
        while True:
            self.run_once()
            time.sleep(interval_s)

    def simulate(self, raw_overrides: dict[str, Any]) -> dict[str, object]:
        merged = _deep_merge(json.loads(json.dumps(self.config.raw)), raw_overrides)
        merged.setdefault("runtime", {})
        merged["runtime"]["state_dir"] = str(self.state_dir)
        simulation = SchedulerService(RuntimeConfig(raw=merged, path=self.config.path), persist_runtime_state=False)
        return simulation.run_once(persist=False)

    def _build_snapshot(self, plan_input: PlannerInput, result: PlannerResult) -> dict[str, object]:
        probability_map = {scenario.scenario_id: scenario.probability for scenario in plan_input.producer.scenarios}
        expected_buckets: dict[int, dict[str, float]] = defaultdict(lambda: {
            "battery_soc_kwh": 0.0,
            "battery_charge_kwh": 0.0,
            "battery_discharge_kwh": 0.0,
            "reserve_target_kwh": 0.0,
            "emergency_floor_kwh": plan_input.battery.emergency_floor_kwh,
            "import_kwh": 0.0,
            "export_kwh": 0.0,
            "curtail_kwh": 0.0,
            "solar_kwh": 0.0,
            "fixed_load_kwh": 0.0,
            "flexible_load_kwh": 0.0,
            "tesla_kwh": 0.0,
            "import_price_czk_per_kwh": 0.0,
            "export_price_czk_per_kwh": 0.0,
        })
        for scenario in plan_input.producer.scenarios:
            for bucket_index, solar_kwh in enumerate(scenario.solar_generation_kwh):
                expected_buckets[bucket_index]["solar_kwh"] += scenario.probability * solar_kwh
                expected_buckets[bucket_index]["fixed_load_kwh"] += scenario.probability * plan_input.demand.fixed_demand_kwh[bucket_index]
                expected_buckets[bucket_index]["reserve_target_kwh"] = plan_input.battery.reserve_target_kwh[bucket_index]
                expected_buckets[bucket_index]["import_price_czk_per_kwh"] = plan_input.prices.import_prices[bucket_index]
                expected_buckets[bucket_index]["export_price_czk_per_kwh"] = plan_input.prices.export_prices[bucket_index]
        for bucket in result.battery_plan:
            probability = probability_map[bucket.scenario_id]
            row = expected_buckets[bucket.bucket_index]
            row["battery_soc_kwh"] += probability * bucket.soc_kwh
            row["battery_charge_kwh"] += probability * bucket.charge_kwh
            row["battery_discharge_kwh"] += probability * bucket.discharge_kwh
            row["import_kwh"] += probability * bucket.import_kwh
            row["export_kwh"] += probability * bucket.export_kwh
            row["curtail_kwh"] += probability * bucket.curtail_kwh

        scenario_band_lookup = {
            (band.band_id, band.scenario_id): band
            for band in plan_input.demand.demand_bands
            if band.scenario_id is not None
        }
        generic_band_lookup = {
            band.band_id: band
            for band in plan_input.demand.demand_bands
            if band.scenario_id is None
        }

        def resolve_band(band_id: str, scenario_id: str):
            return scenario_band_lookup.get((band_id, scenario_id)) or generic_band_lookup.get(band_id)

        band_served: dict[tuple[str, str], float] = defaultdict(float)
        for allocation in result.band_allocations:
            band_served[(allocation.band_id, allocation.scenario_id)] += allocation.served_kwh
            band = resolve_band(allocation.band_id, allocation.scenario_id)
            if band is None:
                continue
            probability = probability_map.get(allocation.scenario_id, 0.0)
            expected_buckets[allocation.bucket_index]["flexible_load_kwh"] += probability * allocation.served_kwh
            if band.asset_id.startswith("tesla"):
                expected_buckets[allocation.bucket_index]["tesla_kwh"] += probability * allocation.served_kwh

        grouped_bands: dict[str, dict[str, object]] = {}
        for shortfall in result.shortfalls:
            band = resolve_band(shortfall.band_id, shortfall.scenario_id)
            if band is None:
                continue
            group_band_id = band.logical_band_id or band.band_id
            probability = probability_map.get(shortfall.scenario_id, 0.0)
            group = grouped_bands.setdefault(
                group_band_id,
                {
                    "band_id": group_band_id,
                    "asset_id": band.asset_id,
                    "display_name": band.display_name or band.band_id,
                    "required_level": band.required_level,
                    "deadline_index": band.deadline_index,
                    "marginal_value_czk_per_kwh": band.marginal_value_czk_per_kwh,
                    "confidence": band.confidence,
                    "confidence_source": band.confidence_source or "all_scenarios",
                    "metadata": band.metadata,
                    "applicable_probability": 0.0,
                    "weighted_target_quantity_kwh": 0.0,
                    "weighted_served_quantity_kwh": 0.0,
                    "weighted_shortfall_kwh": 0.0,
                },
            )
            group["applicable_probability"] = float(group["applicable_probability"]) + probability
            group["weighted_target_quantity_kwh"] = float(group["weighted_target_quantity_kwh"]) + probability * band.target_quantity_kwh
            group["weighted_served_quantity_kwh"] = float(group["weighted_served_quantity_kwh"]) + probability * band_served[(shortfall.band_id, shortfall.scenario_id)]
            group["weighted_shortfall_kwh"] = float(group["weighted_shortfall_kwh"]) + probability * shortfall.unmet_kwh

        bands = []
        for band in grouped_bands.values():
            applicable_probability = max(float(band.pop("applicable_probability")), 1e-9)
            weighted_target_quantity = float(band.pop("weighted_target_quantity_kwh"))
            weighted_served_quantity = float(band.pop("weighted_served_quantity_kwh"))
            weighted_shortfall = float(band.pop("weighted_shortfall_kwh"))
            bands.append(
                {
                    **band,
                    "scenario_probability": applicable_probability,
                    "target_quantity_kwh": weighted_target_quantity / applicable_probability,
                    "served_quantity_kwh": weighted_served_quantity / applicable_probability,
                    "shortfall_kwh": weighted_shortfall / applicable_probability,
                }
            )
        bands.sort(key=lambda item: (-int(bool(item["required_level"])), int(item["deadline_index"]), item["display_name"]))

        telemetry_timeline = [
            {"bucket_index": bucket_index, **values}
            for bucket_index, values in sorted(expected_buckets.items())
            if bucket_index < min(96, plan_input.horizon_buckets)
        ]
        next_tesla_day = None
        for entry in plan_input.demand.tesla_calendar_summary:
            departure_time = entry.get("departure_time")
            if departure_time is None:
                continue
            departure_at = datetime.combine(
                datetime.fromisoformat(str(entry["date"])).date(),
                time.fromisoformat(str(departure_time)),
                tzinfo=plan_input.created_at.tzinfo,
            )
            if departure_at >= plan_input.created_at:
                next_tesla_day = entry
                break
        if next_tesla_day is None:
            next_tesla_day = next((entry for entry in plan_input.demand.tesla_calendar_summary if entry["departure_time"] is not None), None)

        summary = {
            "planner_status": "ok",
            "planner_timestamp": plan_input.created_at.isoformat(),
            "objective_value_czk": result.objective_value_czk,
            "bucket_minutes": plan_input.bucket_minutes,
            "horizon_buckets": plan_input.horizon_buckets,
            "battery_soc_kwh": telemetry_timeline[0]["battery_soc_kwh"] if telemetry_timeline else plan_input.battery.initial_soc_kwh,
            "battery_capacity_kwh": plan_input.battery.max_soc_kwh,
            "battery_reserve_kwh": telemetry_timeline[0]["reserve_target_kwh"] if telemetry_timeline else plan_input.battery.reserve_target_kwh[0],
            "battery_emergency_floor_kwh": plan_input.battery.emergency_floor_kwh,
            "current_import_kwh": telemetry_timeline[0]["import_kwh"] if telemetry_timeline else 0.0,
            "current_export_kwh": telemetry_timeline[0]["export_kwh"] if telemetry_timeline else 0.0,
            "current_flexible_load_kwh": telemetry_timeline[0]["flexible_load_kwh"] if telemetry_timeline else 0.0,
            "current_tesla_kwh": telemetry_timeline[0]["tesla_kwh"] if telemetry_timeline else 0.0,
            "grid_available": plan_input.grid_available,
            "next_tesla_day": next_tesla_day,
        }
        return {
            "created_at": plan_input.created_at.isoformat(),
            "summary": summary,
            "telemetry_timeline": telemetry_timeline,
            "bands": bands,
            "scenario_summary": [
                {"scenario_id": scenario.scenario_id, "probability": scenario.probability, "labels": scenario.labels}
                for scenario in plan_input.producer.scenarios
            ],
            "tesla_calendar_summary": plan_input.demand.tesla_calendar_summary,
            "shortfalls": [asdict(item) for item in result.shortfalls],
            "battery_plan": [asdict(item) for item in result.battery_plan[: min(96, len(result.battery_plan))]],
            "band_allocations": [asdict(item) for item in result.band_allocations[:300]],
        }

def _deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            base[key] = _deep_merge(base[key], value)
        else:
            base[key] = value
    return base
