from __future__ import annotations

from collections import defaultdict

from energy_scheduler.adapters.base import BatteryAdapter, DemandAdapter, PriceAdapter, ProducerAdapter
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
    def __init__(self, config: RuntimeConfig):
        self._config = config

    def get_demand(self, horizon_buckets: int, bucket_minutes: int) -> DemandPlanInput:
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
                            scenario_id=scenario_id,
                        )
                    )
        return DemandPlanInput(demand_bands=bands, fixed_demand_kwh=fixed)


def validate_scenario_coverage(config: RuntimeConfig) -> None:
    scenario_weights = config.assets.get("scenario_weights", {})
    for demand in config.assets.get("demands", []):
        for band in demand["bands"]:
            for scenario_id in band.get("scenario_ids", []):
                if scenario_id is None:
                    continue
                if scenario_id not in scenario_weights:
                    raise ValueError(f"missing scenario weight for demand scenario '{scenario_id}'")
    duplicates = defaultdict(int)
    for scenario_id in scenario_weights:
        duplicates[scenario_id] += 1
    for scenario_id, count in duplicates.items():
        if count > 1:
            raise ValueError(f"duplicate solar scenario id '{scenario_id}'")
