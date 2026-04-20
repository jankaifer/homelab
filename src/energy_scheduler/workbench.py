from __future__ import annotations

import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

from energy_scheduler.calendar import build_default_calendar, refresh_calendar_window
from energy_scheduler.config import RuntimeConfig
from energy_scheduler.files import write_json_atomic
from energy_scheduler.service import SchedulerService


SCENARIO_ID_PATTERN = re.compile(r"^[a-z0-9-]+$")
DEFAULT_WORKBENCH_HORIZON_BUCKETS = 96


def _deep_copy(value: Any) -> Any:
    return json.loads(json.dumps(value))


def _fill_or_trim(values: list[Any], length: int, fill_value: Any) -> list[Any]:
    if length <= 0:
        return []
    if not values:
        return [fill_value for _ in range(length)]
    normalized = list(values[:length])
    while len(normalized) < length:
        normalized.append(normalized[-1] if normalized else fill_value)
    return normalized


def _scenario_slug() -> str:
    return f"scenario-{uuid4().hex[:8]}"


def _default_simulation_start() -> datetime:
    now = datetime.now().astimezone().replace(second=0, microsecond=0)
    return now.replace(hour=0, minute=0)


def _parse_iso_datetime(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise ValueError("simulation_start_at must include timezone information")
    return parsed


def _error(path: str, message: str) -> dict[str, str]:
    return {"path": path, "message": message}


def _normalize_runtime(config: dict[str, Any], runtime_dir: Path) -> None:
    runtime = config.setdefault("runtime", {})
    runtime["state_dir"] = str(runtime_dir)
    runtime["grid_available"] = bool(runtime.get("grid_available", True))


def _normalize_scheduler(config: dict[str, Any], errors: list[dict[str, str]]) -> int:
    scheduler = config.setdefault("scheduler", {})
    try:
        horizon_buckets = int(scheduler.get("horizon_buckets", DEFAULT_WORKBENCH_HORIZON_BUCKETS))
    except (TypeError, ValueError):
        errors.append(_error("config.scheduler.horizon_buckets", "Horizon buckets must be an integer."))
        horizon_buckets = DEFAULT_WORKBENCH_HORIZON_BUCKETS
    if horizon_buckets <= 0:
        errors.append(_error("config.scheduler.horizon_buckets", "Horizon buckets must be greater than zero."))
        horizon_buckets = DEFAULT_WORKBENCH_HORIZON_BUCKETS
    scheduler["horizon_buckets"] = horizon_buckets
    scheduler["bucket_minutes"] = 15
    scheduler["loop_interval_seconds"] = int(scheduler.get("loop_interval_seconds", 60))
    scheduler["churn_penalty_czk_per_kw_change"] = float(scheduler.get("churn_penalty_czk_per_kw_change", 0.01))
    return horizon_buckets


def _normalize_prices(config: dict[str, Any], horizon_buckets: int, errors: list[dict[str, str]]) -> None:
    forecasts = config.setdefault("forecasts", {})
    prices = forecasts.setdefault("prices", {})
    for key in ("import_czk_per_kwh", "export_czk_per_kwh"):
        raw_values = [float(value) for value in prices.get(key, [])]
        prices[key] = _fill_or_trim(raw_values, horizon_buckets, 0.0)
        if not prices[key]:
            errors.append(_error(f"config.forecasts.prices.{key}", "Price series cannot be empty."))


def _normalize_solar(config: dict[str, Any], horizon_buckets: int, errors: list[dict[str, str]]) -> None:
    forecasts = config.setdefault("forecasts", {})
    solar = forecasts.setdefault("solar", {})
    solar["asset_id"] = str(solar.get("asset_id", "solar-main"))
    solar["export_allowed"] = bool(solar.get("export_allowed", True))
    solar["curtailment_allowed"] = bool(solar.get("curtailment_allowed", True))

    raw_scenarios = solar.get("scenarios", [])
    normalized = []
    seen_ids: set[str] = set()
    positive_probability = 0.0
    for index, scenario in enumerate(raw_scenarios):
        scenario_id = str(scenario.get("id", "")).strip()
        if not scenario_id:
            errors.append(_error(f"config.forecasts.solar.scenarios[{index}].id", "Scenario id is required."))
            scenario_id = f"solar-{index + 1}"
        if scenario_id in seen_ids:
            errors.append(_error(f"config.forecasts.solar.scenarios[{index}].id", "Scenario ids must be unique."))
        seen_ids.add(scenario_id)
        probability = float(scenario.get("probability", 0.0))
        if probability < 0:
            errors.append(_error(f"config.forecasts.solar.scenarios[{index}].probability", "Probability cannot be negative."))
        positive_probability += max(probability, 0.0)
        generation = _fill_or_trim([float(value) for value in scenario.get("generation_kwh", [])], horizon_buckets, 0.0)
        normalized.append(
            {
                "id": scenario_id,
                "probability": probability,
                "generation_kwh": generation,
                "labels": dict(scenario.get("labels", {})),
            }
        )
    if not normalized:
        errors.append(_error("config.forecasts.solar.scenarios", "At least one solar scenario is required."))
        normalized = [
            {
                "id": "solar-expected",
                "probability": 1.0,
                "generation_kwh": [0.0] * horizon_buckets,
                "labels": {"kind": "expected"},
            }
        ]
        positive_probability = 1.0
    if positive_probability <= 0:
        errors.append(_error("config.forecasts.solar.scenarios", "At least one solar scenario must have positive probability."))
    solar["scenarios"] = normalized


def _normalize_battery(config: dict[str, Any], horizon_buckets: int, errors: list[dict[str, str]]) -> None:
    assets = config.setdefault("assets", {})
    battery = assets.setdefault("battery", {})
    battery["asset_id"] = str(battery.get("asset_id", "home-battery"))
    for key in ("capacity_kwh", "initial_soc_kwh", "min_soc_kwh", "max_soc_kwh", "max_charge_kw", "max_discharge_kw", "charge_efficiency", "discharge_efficiency", "cycle_cost_czk_per_kwh", "emergency_floor_kwh"):
        battery[key] = float(battery.get(key, 0.0))
    battery["grid_charge_allowed"] = bool(battery.get("grid_charge_allowed", True))
    battery["export_discharge_allowed"] = bool(battery.get("export_discharge_allowed", True))
    battery["reserve_target_kwh"] = _fill_or_trim([float(value) for value in battery.get("reserve_target_kwh", [])], horizon_buckets, battery.get("emergency_floor_kwh", 0.0))
    battery["reserve_value_czk_per_kwh"] = _fill_or_trim([float(value) for value in battery.get("reserve_value_czk_per_kwh", [])], horizon_buckets, 0.0)

    if battery["capacity_kwh"] <= 0:
        errors.append(_error("config.assets.battery.capacity_kwh", "Battery capacity must be greater than zero."))
    if battery["min_soc_kwh"] > battery["max_soc_kwh"]:
        errors.append(_error("config.assets.battery.min_soc_kwh", "Battery minimum SoC cannot exceed maximum SoC."))
    if battery["initial_soc_kwh"] < battery["min_soc_kwh"] or battery["initial_soc_kwh"] > battery["max_soc_kwh"]:
        errors.append(_error("config.assets.battery.initial_soc_kwh", "Initial SoC must stay within min/max SoC."))
    if battery["emergency_floor_kwh"] < battery["min_soc_kwh"] or battery["emergency_floor_kwh"] > battery["max_soc_kwh"]:
        errors.append(_error("config.assets.battery.emergency_floor_kwh", "Emergency floor must stay within min/max SoC."))


def _normalize_base_load(config: dict[str, Any], horizon_buckets: int) -> None:
    assets = config.setdefault("assets", {})
    base_load = assets.setdefault("base_load", {})
    base_load["fixed_demand_kwh"] = _fill_or_trim([float(value) for value in base_load.get("fixed_demand_kwh", [])], horizon_buckets, 0.0)


def _normalize_tesla(config: dict[str, Any], simulation_start_at: datetime, errors: list[dict[str, str]]) -> None:
    assets = config.setdefault("assets", {})
    tesla = assets.get("tesla")
    if tesla is None:
        return
    tesla["asset_id"] = str(tesla.get("asset_id", "tesla-model-3"))
    for key in (
        "battery_capacity_kwh",
        "current_soc_pct",
        "default_start_soc_pct",
        "charge_power_kw",
        "required_marginal_value_czk_per_kwh",
        "required_unmet_penalty_czk_per_kwh",
        "opportunistic_target_soc_pct",
        "opportunistic_marginal_value_czk_per_kwh",
    ):
        tesla[key] = float(tesla.get(key, 0.0))

    recurring_schedule = list(tesla.get("recurring_schedule", []))
    for index, entry in enumerate(recurring_schedule):
        try:
            entry["weekday"] = int(entry["weekday"])
            entry["target_soc_pct"] = float(entry["target_soc_pct"])
            entry["confidence"] = float(entry.get("confidence", 0.35))
            entry["departure_time"] = str(entry["departure_time"])
        except (KeyError, TypeError, ValueError):
            errors.append(_error(f"config.assets.tesla.recurring_schedule[{index}]", "Recurring Tesla schedule entries must include weekday, departure_time, target_soc_pct, and confidence."))
    tesla["recurring_schedule"] = recurring_schedule

    if tesla.get("calendar") is None:
        tesla["calendar"] = build_default_calendar(recurring_schedule, today=simulation_start_at.date())
    else:
        tesla["calendar"] = refresh_calendar_window(
            tesla["calendar"],
            recurring_schedule,
            today=simulation_start_at.date(),
        )


def _normalize_demands(config: dict[str, Any], horizon_buckets: int, errors: list[dict[str, str]]) -> None:
    assets = config.setdefault("assets", {})
    normalized_demands = []
    for demand_index, demand in enumerate(assets.get("demands", [])):
        asset_id = str(demand.get("asset_id", "")).strip()
        if not asset_id:
            errors.append(_error(f"config.assets.demands[{demand_index}].asset_id", "Demand asset_id is required."))
            asset_id = f"demand-{demand_index + 1}"
        normalized_bands = []
        for band_index, band in enumerate(demand.get("bands", [])):
            band_id = str(band.get("id", "")).strip()
            if not band_id:
                errors.append(_error(f"config.assets.demands[{demand_index}].bands[{band_index}].id", "Demand band id is required."))
                band_id = f"{asset_id}-band-{band_index + 1}"
            normalized_band = {
                "id": band_id,
                "display_name": str(band.get("display_name", band_id)),
                "start_index": int(band.get("start_index", 0)),
                "deadline_index": int(band.get("deadline_index", horizon_buckets - 1)),
                "earliest_start_index": int(band.get("earliest_start_index", band.get("start_index", 0))),
                "latest_finish_index": int(band.get("latest_finish_index", band.get("deadline_index", horizon_buckets - 1))),
                "target_quantity_kwh": float(band.get("target_quantity_kwh", 0.0)),
                "min_power_kw": float(band.get("min_power_kw", 0.0)),
                "max_power_kw": float(band.get("max_power_kw", 0.0)),
                "interruptible": bool(band.get("interruptible", True)),
                "preemptible": bool(band.get("preemptible", True)),
                "marginal_value_czk_per_kwh": float(band.get("marginal_value_czk_per_kwh", 0.0)),
                "unmet_penalty_czk_per_kwh": float(band.get("unmet_penalty_czk_per_kwh", 0.0)),
                "required_level": bool(band.get("required_level", False)),
                "quantity_unit": str(band.get("quantity_unit", "kwh")),
            }
            for field in ("start_index", "deadline_index", "earliest_start_index", "latest_finish_index"):
                if normalized_band[field] < 0 or normalized_band[field] >= horizon_buckets:
                    errors.append(
                        _error(
                            f"config.assets.demands[{demand_index}].bands[{band_index}].{field}",
                            f"{field} must stay within the current horizon.",
                        )
                    )
            if normalized_band["earliest_start_index"] > normalized_band["latest_finish_index"]:
                errors.append(
                    _error(
                        f"config.assets.demands[{demand_index}].bands[{band_index}].earliest_start_index",
                        "Earliest start cannot be after latest finish.",
                    )
                )
            normalized_bands.append(normalized_band)
        normalized_demands.append(
            {
                "asset_id": asset_id,
                "display_name": str(demand.get("display_name", asset_id)),
                "bands": normalized_bands,
            }
        )
    assets["demands"] = normalized_demands


def normalize_workbench_config(
    config: dict[str, Any],
    *,
    simulation_start_at: datetime,
    runtime_dir: Path,
) -> tuple[dict[str, Any], list[dict[str, str]], list[str]]:
    normalized = _deep_copy(config)
    errors: list[dict[str, str]] = []
    warnings: list[str] = []

    _normalize_runtime(normalized, runtime_dir)
    horizon_buckets = _normalize_scheduler(normalized, errors)
    _normalize_prices(normalized, horizon_buckets, errors)
    _normalize_solar(normalized, horizon_buckets, errors)
    _normalize_battery(normalized, horizon_buckets, errors)
    _normalize_base_load(normalized, horizon_buckets)
    _normalize_tesla(normalized, simulation_start_at, errors)
    _normalize_demands(normalized, horizon_buckets, errors)

    return normalized, errors, warnings


class WorkbenchStore:
    def __init__(self, state_dir: Path, base_config: RuntimeConfig, live_calendar_provider):
        self.state_dir = state_dir
        self.base_config = base_config
        self.live_calendar_provider = live_calendar_provider
        self.root = self.state_dir / "workbench"
        self.scenario_root = self.root / "scenarios"
        self.result_root = self.root / "results"
        self.runtime_root = self.root / "runtime"

    def ensure_dirs(self) -> None:
        self.scenario_root.mkdir(parents=True, exist_ok=True)
        self.result_root.mkdir(parents=True, exist_ok=True)
        self.runtime_root.mkdir(parents=True, exist_ok=True)

    def list_scenarios(self) -> list[dict[str, Any]]:
        self.ensure_dirs()
        scenarios = []
        for path in sorted(self.scenario_root.glob("*.json")):
            scenario = self._load_json(path)
            result = self.get_result(scenario["id"])
            scenarios.append(
                {
                    "id": scenario["id"],
                    "name": scenario["name"],
                    "description": scenario.get("description", ""),
                    "created_at": scenario["created_at"],
                    "updated_at": scenario["updated_at"],
                    "simulation_start_at": scenario["simulation_start_at"],
                    "last_run_at": result.get("run_at") if result else None,
                    "objective_value_czk": result.get("snapshot", {}).get("summary", {}).get("objective_value_czk") if result else None,
                }
            )
        scenarios.sort(key=lambda item: (item["updated_at"], item["name"]))
        scenarios.reverse()
        return scenarios

    def create_scenario(self, name: str | None = None) -> dict[str, Any]:
        self.ensure_dirs()
        scenario_id = _scenario_slug()
        now = datetime.now().astimezone().replace(second=0, microsecond=0)
        simulation_start_at = _default_simulation_start()
        config = _deep_copy(self.base_config.raw)
        config.setdefault("scheduler", {})["horizon_buckets"] = DEFAULT_WORKBENCH_HORIZON_BUCKETS
        tesla = config.setdefault("assets", {}).get("tesla")
        if tesla is not None:
            tesla["calendar"] = self.live_calendar_provider()
        scenario = {
            "id": scenario_id,
            "name": name or self._default_name(),
            "description": "",
            "created_at": now.isoformat(),
            "updated_at": now.isoformat(),
            "simulation_start_at": simulation_start_at.isoformat(),
            "config": config,
        }
        return self.save_scenario(scenario_id, scenario, creating=True)

    def clone_scenario(self, scenario_id: str) -> dict[str, Any]:
        source = self.get_scenario(scenario_id)
        clone = _deep_copy(source)
        now = datetime.now().astimezone().replace(second=0, microsecond=0)
        clone["id"] = _scenario_slug()
        clone["name"] = f"{source['name']} copy"
        clone["created_at"] = now.isoformat()
        clone["updated_at"] = now.isoformat()
        return self.save_scenario(clone["id"], clone, creating=True)

    def get_scenario(self, scenario_id: str) -> dict[str, Any]:
        return self._load_json(self._scenario_path(scenario_id))

    def save_scenario(self, scenario_id: str, payload: dict[str, Any], creating: bool = False) -> dict[str, Any]:
        self.ensure_dirs()
        if not SCENARIO_ID_PATTERN.match(scenario_id):
            raise ValueError("invalid scenario id")
        simulation_start_at = _parse_iso_datetime(str(payload["simulation_start_at"]))
        normalized_config, errors, warnings = normalize_workbench_config(
            payload["config"],
            simulation_start_at=simulation_start_at,
            runtime_dir=self.runtime_root / scenario_id,
        )
        if errors:
            raise ValueError(json.dumps({"errors": errors, "warnings": warnings}))

        now = datetime.now().astimezone().isoformat()
        existing = None if creating else self.get_scenario(scenario_id)
        scenario = {
            "id": scenario_id,
            "name": str(payload.get("name", "")).strip() or self._default_name(),
            "description": str(payload.get("description", "")),
            "created_at": existing["created_at"] if existing is not None else payload.get("created_at", now),
            "updated_at": now,
            "simulation_start_at": simulation_start_at.isoformat(),
            "config": normalized_config,
        }
        write_json_atomic(self._scenario_path(scenario_id), scenario)
        return scenario

    def delete_scenario(self, scenario_id: str) -> None:
        self._scenario_path(scenario_id).unlink(missing_ok=True)
        self._result_path(scenario_id).unlink(missing_ok=True)

    def get_result(self, scenario_id: str) -> dict[str, Any] | None:
        path = self._result_path(scenario_id)
        if not path.exists():
            return None
        return self._load_json(path)

    def run_scenario(self, scenario_id: str) -> dict[str, Any]:
        scenario = self.get_scenario(scenario_id)
        simulation_start_at = _parse_iso_datetime(scenario["simulation_start_at"])
        normalized_config, errors, warnings = normalize_workbench_config(
            scenario["config"],
            simulation_start_at=simulation_start_at,
            runtime_dir=self.runtime_root / scenario_id,
        )
        if errors:
            raise ValueError(json.dumps({"errors": errors, "warnings": warnings}))

        scheduler = SchedulerService(
            RuntimeConfig(raw=normalized_config, path=self.base_config.path),
            persist_runtime_state=False,
        )
        snapshot = scheduler.run_once(persist=False, start_at=simulation_start_at)
        result = {
            "scenario_id": scenario_id,
            "run_at": datetime.now().astimezone().isoformat(),
            "simulation_start_at": simulation_start_at.isoformat(),
            "validation_errors": [],
            "validation_warnings": warnings,
            "snapshot": snapshot,
            "band_fulfillment": snapshot.get("bands", []),
            "scenario_assumptions": {
                "solar": [
                    {
                        "id": item["id"],
                        "probability": float(item["probability"]),
                        "labels": item.get("labels", {}),
                    }
                    for item in normalized_config["forecasts"]["solar"]["scenarios"]
                ],
                "tesla_calendar": normalized_config.get("assets", {}).get("tesla", {}).get("calendar", {}).get("days", []),
                "grid_available": bool(normalized_config.get("runtime", {}).get("grid_available", True)),
            },
            "constraint_debug": {
                "warnings": warnings,
                "shortfalls": snapshot.get("shortfalls", []),
            },
        }
        write_json_atomic(self._result_path(scenario_id), result)
        write_json_atomic(self._scenario_path(scenario_id), {**scenario, "updated_at": datetime.now().astimezone().isoformat(), "config": normalized_config})
        return result

    def _default_name(self) -> str:
        existing = {item["name"] for item in self.list_scenarios()}
        index = 1
        while f"Scenario {index}" in existing:
            index += 1
        return f"Scenario {index}"

    def _scenario_path(self, scenario_id: str) -> Path:
        return self.scenario_root / f"{scenario_id}.json"

    def _result_path(self, scenario_id: str) -> Path:
        return self.result_root / f"{scenario_id}.json"

    @staticmethod
    def _load_json(path: Path) -> dict[str, Any]:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
