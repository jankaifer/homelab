from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum


class DemandUnit(str, Enum):
    KWH = "kwh"
    SOC_PCT = "soc_pct"
    TEMPERATURE_C = "temperature_c"
    GENERIC = "generic"


@dataclass
class PriceSeries:
    import_prices: list[float]
    export_prices: list[float]


@dataclass
class Scenario:
    scenario_id: str
    probability: float
    solar_generation_kwh: list[float]
    labels: dict[str, str] = field(default_factory=dict)


@dataclass
class ProducerForecast:
    asset_id: str
    scenarios: list[Scenario]
    export_allowed: bool = True
    curtailment_allowed: bool = True


@dataclass
class BatteryState:
    asset_id: str
    capacity_kwh: float
    initial_soc_kwh: float
    min_soc_kwh: float
    max_soc_kwh: float
    max_charge_kw: float
    max_discharge_kw: float
    charge_efficiency: float
    discharge_efficiency: float
    cycle_cost_czk_per_kwh: float
    grid_charge_allowed: bool
    export_discharge_allowed: bool
    emergency_floor_kwh: float
    reserve_target_kwh: list[float]
    reserve_value_czk_per_kwh: list[float]


@dataclass
class DemandBand:
    band_id: str
    asset_id: str
    start_index: int
    deadline_index: int
    earliest_start_index: int
    latest_finish_index: int
    target_quantity_kwh: float
    min_power_kw: float
    max_power_kw: float
    interruptible: bool
    preemptible: bool
    marginal_value_czk_per_kwh: float
    unmet_penalty_czk_per_kwh: float
    required_level: bool
    quantity_unit: DemandUnit = DemandUnit.KWH
    display_name: str | None = None
    logical_band_id: str | None = None
    confidence: float | None = None
    confidence_source: str | None = None
    metadata: dict[str, str] = field(default_factory=dict)
    scenario_id: str | None = None


@dataclass
class DemandPlanInput:
    demand_bands: list[DemandBand]
    fixed_demand_kwh: list[float]
    scenario_weights: dict[str, float] = field(default_factory=dict)
    scenario_labels: dict[str, dict[str, str]] = field(default_factory=dict)
    tesla_calendar_summary: list[dict[str, object]] = field(default_factory=list)


@dataclass
class PlannerInput:
    created_at: datetime
    bucket_minutes: int
    horizon_buckets: int
    prices: PriceSeries
    producer: ProducerForecast
    battery: BatteryState
    demand: DemandPlanInput
    grid_available: bool = True
    churn_penalty_czk_per_kw_change: float = 0.0
    previous_battery_target_kw: float = 0.0


@dataclass
class BandAllocation:
    band_id: str
    scenario_id: str
    bucket_index: int
    served_kwh: float


@dataclass
class BatteryBucketPlan:
    scenario_id: str
    bucket_index: int
    charge_kwh: float
    discharge_kwh: float
    soc_kwh: float
    import_kwh: float
    export_kwh: float
    curtail_kwh: float


@dataclass
class BandShortfall:
    band_id: str
    scenario_id: str
    unmet_kwh: float


@dataclass
class PlannerResult:
    objective_value_czk: float
    battery_plan: list[BatteryBucketPlan]
    band_allocations: list[BandAllocation]
    shortfalls: list[BandShortfall]
    summary: dict[str, float]
