from __future__ import annotations

from collections import defaultdict
from datetime import datetime, date, time

from energy_scheduler.adapters.base import BatteryAdapter, DemandAdapter, PriceAdapter, ProducerAdapter
from energy_scheduler.calendar import build_tesla_scenarios, load_or_create_calendar, refresh_calendar_window
from energy_scheduler.config import RuntimeConfig
from energy_scheduler.domain import BatteryState, DemandBand, DemandPlanInput, DemandUnit, PriceSeries, ProducerForecast, Scenario


def _fill_or_trim(values: list[float], length: int) -> list[float]:
    if not values:
        return [0.0] * length
    if len(values) >= length:
        return values[:length]
    fill = values[-1]
    return values + [fill] * (length - len(values))


class ConfigPriceAdapter(PriceAdapter):
    def __init__(self, config: RuntimeConfig):
        self._config = config

    def get_prices(self, horizon_buckets: int) -> PriceSeries:
        prices = self._config.forecasts["prices"]
        return PriceSeries(
            import_prices=_fill_or_trim([float(v) for v in prices["import_czk_per_kwh"]], horizon_buckets),
            export_prices=_fill_or_trim([float(v) for v in prices["export_czk_per_kwh"]], horizon_buckets),
        )


class ConfigSolarAdapter(ProducerAdapter):
    def __init__(self, config: RuntimeConfig):
        self._config = config

    def get_forecast(self, horizon_buckets: int) -> ProducerForecast:
        solar = self._config.forecasts["solar"]
        scenarios: list[Scenario] = []
        for entry in solar["scenarios"]:
            scenarios.append(
                Scenario(
                    scenario_id=entry["id"],
                    probability=float(entry["probability"]),
                    solar_generation_kwh=_fill_or_trim([float(v) for v in entry["generation_kwh"]], horizon_buckets),
                    labels=entry.get("labels", {}),
                )
            )
        total_probability = sum(item.probability for item in scenarios)
        if total_probability <= 0:
            raise ValueError("solar scenario probabilities must be positive")
        normalized = [
            Scenario(
                scenario_id=item.scenario_id,
                probability=item.probability / total_probability,
                solar_generation_kwh=item.solar_generation_kwh,
                labels=item.labels,
            )
            for item in scenarios
        ]
        return ProducerForecast(
            asset_id=solar.get("asset_id", "solar"),
            scenarios=normalized,
            export_allowed=bool(solar.get("export_allowed", True)),
            curtailment_allowed=bool(solar.get("curtailment_allowed", True)),
        )


class ConfigBatteryAdapter(BatteryAdapter):
    def __init__(self, config: RuntimeConfig):
        self._config = config

    def get_battery(self, horizon_buckets: int) -> BatteryState:
        battery = self._config.assets["battery"]
        reserve = _fill_or_trim([float(v) for v in battery["reserve_value_czk_per_kwh"]], horizon_buckets)
        return BatteryState(
            asset_id=battery.get("asset_id", "battery"),
            capacity_kwh=float(battery["capacity_kwh"]),
            initial_soc_kwh=float(battery["initial_soc_kwh"]),
            min_soc_kwh=float(battery["min_soc_kwh"]),
            max_soc_kwh=float(battery["max_soc_kwh"]),
            max_charge_kw=float(battery["max_charge_kw"]),
            max_discharge_kw=float(battery["max_discharge_kw"]),
            charge_efficiency=float(battery.get("charge_efficiency", 1.0)),
            discharge_efficiency=float(battery.get("discharge_efficiency", 1.0)),
            cycle_cost_czk_per_kwh=float(battery.get("cycle_cost_czk_per_kwh", 0.0)),
            grid_charge_allowed=bool(battery.get("grid_charge_allowed", True)),
            export_discharge_allowed=bool(battery.get("export_discharge_allowed", True)),
            emergency_floor_kwh=float(battery.get("emergency_floor_kwh", battery["min_soc_kwh"])),
            reserve_target_kwh=_fill_or_trim(
                [float(v) for v in battery.get("reserve_target_kwh", [float(battery.get("emergency_floor_kwh", battery["min_soc_kwh"]))])],
                horizon_buckets,
            ),
            reserve_value_czk_per_kwh=reserve,
        )


class ConfigDemandAdapter(DemandAdapter):
    def __init__(self, config: RuntimeConfig, persist_runtime_state: bool = True):
        self._config = config
        self._persist_runtime_state = persist_runtime_state

    def get_demand(self, horizon_buckets: int, bucket_minutes: int, start_at: datetime) -> DemandPlanInput:
        assets = self._config.assets
        fixed = _fill_or_trim([float(v) for v in assets["base_load"]["fixed_demand_kwh"]], horizon_buckets)
        bands: list[DemandBand] = []

        for demand in assets.get("demands", []):
            for band in demand["bands"]:
                start_index = int(band.get("start_index", 0))
                deadline_index = min(int(band.get("deadline_index", horizon_buckets - 1)), horizon_buckets - 1)
                earliest_start_index = int(band.get("earliest_start_index", start_index))
                latest_finish_index = min(int(band.get("latest_finish_index", deadline_index)), horizon_buckets - 1)
                scenarios = band.get("scenario_ids", [None])
                for scenario_id in scenarios:
                    bands.append(
                        DemandBand(
                            band_id=band["id"] if scenario_id is None else f"{band['id']}:{scenario_id}",
                            asset_id=demand["asset_id"],
                            start_index=start_index,
                            deadline_index=deadline_index,
                            earliest_start_index=earliest_start_index,
                            latest_finish_index=latest_finish_index,
                            target_quantity_kwh=float(band["target_quantity_kwh"]),
                            min_power_kw=float(band.get("min_power_kw", 0.0)),
                            max_power_kw=float(band["max_power_kw"]),
                            interruptible=bool(band.get("interruptible", True)),
                            preemptible=bool(band.get("preemptible", True)),
                            marginal_value_czk_per_kwh=float(band["marginal_value_czk_per_kwh"]),
                            unmet_penalty_czk_per_kwh=float(band["unmet_penalty_czk_per_kwh"]),
                            required_level=bool(band.get("required_level", False)),
                            quantity_unit=DemandUnit(band.get("quantity_unit", "kwh")),
                            display_name=band.get("display_name"),
                            logical_band_id=band.get("id"),
                            scenario_id=scenario_id,
                        )
                    )

        scenario_weights: dict[str, float] = {}
        scenario_labels: dict[str, dict[str, str]] = {}
        tesla_calendar_summary: list[dict[str, object]] = []

        tesla = assets.get("tesla")
        if tesla is not None:
            recurring_schedule = tesla.get("recurring_schedule", [])
            if tesla.get("calendar") is not None:
                calendar = refresh_calendar_window(
                    tesla["calendar"],
                    recurring_schedule,
                    today=start_at.date(),
                )
            else:
                calendar = load_or_create_calendar(
                    state_dir=self._config.runtime_path,
                    recurring_schedule=recurring_schedule,
                    persist=self._persist_runtime_state,
                )
            scenario_weights, scenario_labels, tesla_calendar_summary = build_tesla_scenarios(
                calendar=calendar,
                start_at=start_at,
                horizon_buckets=horizon_buckets,
                bucket_minutes=bucket_minutes,
            )
            bands.extend(self._build_tesla_bands(tesla, tesla_calendar_summary, scenario_labels, start_at, horizon_buckets, bucket_minutes))

        return DemandPlanInput(
            demand_bands=bands,
            fixed_demand_kwh=fixed,
            scenario_weights=scenario_weights,
            scenario_labels=scenario_labels,
            tesla_calendar_summary=tesla_calendar_summary,
        )

    def _build_tesla_bands(
        self,
        tesla: dict[str, object],
        calendar_days: list[dict[str, object]],
        scenario_labels: dict[str, dict[str, str]],
        start_at: datetime,
        horizon_buckets: int,
        bucket_minutes: int,
    ) -> list[DemandBand]:
        battery_capacity_kwh = float(tesla["battery_capacity_kwh"])
        current_soc_pct = float(tesla["current_soc_pct"])
        default_start_soc_pct = float(tesla.get("default_start_soc_pct", current_soc_pct))
        charge_power_kw = float(tesla.get("charge_power_kw", 11.0))
        required_marginal = float(tesla.get("required_marginal_value_czk_per_kwh", 5.0))
        required_penalty = float(tesla.get("required_unmet_penalty_czk_per_kwh", 30.0))
        extra_target_soc_pct = float(tesla.get("opportunistic_target_soc_pct", 80.0))
        extra_marginal = float(tesla.get("opportunistic_marginal_value_czk_per_kwh", 2.0))

        calendar_map = {entry["date"]: entry for entry in calendar_days}
        bands: list[DemandBand] = []

        base_extra_kwh = max(0.0, battery_capacity_kwh * (extra_target_soc_pct - current_soc_pct) / 100.0)
        if base_extra_kwh > 0:
            bands.append(
                DemandBand(
                    band_id="tesla-extra",
                    asset_id=str(tesla.get("asset_id", "tesla-model-3")),
                    start_index=0,
                    deadline_index=min(horizon_buckets - 1, int(tesla.get("opportunistic_deadline_index", horizon_buckets - 1))),
                    earliest_start_index=0,
                    latest_finish_index=min(horizon_buckets - 1, int(tesla.get("opportunistic_deadline_index", horizon_buckets - 1))),
                    target_quantity_kwh=base_extra_kwh,
                    min_power_kw=0.0,
                    max_power_kw=charge_power_kw,
                    interruptible=True,
                    preemptible=True,
                    marginal_value_czk_per_kwh=extra_marginal,
                    unmet_penalty_czk_per_kwh=0.0,
                    required_level=False,
                    display_name="Tesla extra charge",
                    logical_band_id="tesla-extra",
                    confidence=1.0,
                    confidence_source="always_available",
                )
            )

        for scenario_id, labels in scenario_labels.items():
            for key, outcome in labels.items():
                if not key.startswith("tesla:") or key.endswith(":mode") or key.endswith(":departure_time") or key.endswith(":target_soc_pct"):
                    continue
                if outcome != "departure":
                    continue
                day_date = key.split(":", 1)[1]
                day_entry = calendar_map.get(day_date)
                if day_entry is None or day_entry["departure_time"] is None or day_entry["target_soc_pct"] is None:
                    continue
                departure_dt = datetime.combine(
                    date.fromisoformat(day_date),
                    time.fromisoformat(str(day_entry["departure_time"])),
                    tzinfo=start_at.tzinfo,
                )
                deadline_index = int((departure_dt - start_at).total_seconds() // (bucket_minutes * 60))
                if deadline_index < 0 or deadline_index >= horizon_buckets:
                    continue
                base_soc_pct = current_soc_pct if day_date == start_at.date().isoformat() else default_start_soc_pct
                target_kwh = max(0.0, battery_capacity_kwh * (float(day_entry["target_soc_pct"]) - base_soc_pct) / 100.0)
                if target_kwh <= 0:
                    continue
                bands.append(
                    DemandBand(
                        band_id=f"tesla-required:{day_date}",
                        asset_id=str(tesla.get("asset_id", "tesla-model-3")),
                        start_index=0,
                        deadline_index=deadline_index,
                        earliest_start_index=0,
                        latest_finish_index=deadline_index,
                        target_quantity_kwh=target_kwh,
                        min_power_kw=0.0,
                        max_power_kw=charge_power_kw,
                        interruptible=True,
                        preemptible=True,
                        marginal_value_czk_per_kwh=required_marginal,
                        unmet_penalty_czk_per_kwh=required_penalty,
                        required_level=True,
                        display_name=f"Tesla departure {day_date}",
                        logical_band_id=f"tesla-required:{day_date}",
                        confidence=float(day_entry["confidence"]),
                        confidence_source=str(day_entry["mode"]),
                        metadata={
                            "date": day_date,
                            "departure_time": str(day_entry["departure_time"]),
                            "target_soc_pct": str(day_entry["target_soc_pct"]),
                        },
                        scenario_id=scenario_id,
                    )
                )
        return bands


def validate_scenario_coverage(config: RuntimeConfig) -> None:
    duplicates = defaultdict(int)
    for scenario in config.forecasts["solar"]["scenarios"]:
        duplicates[str(scenario["id"])] += 1
    for scenario_id, count in duplicates.items():
        if count > 1:
            raise ValueError(f"duplicate solar scenario id '{scenario_id}'")
