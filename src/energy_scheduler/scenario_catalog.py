from __future__ import annotations

import math
from datetime import datetime, timedelta
from typing import Any

from energy_scheduler.config import RuntimeConfig


SCENARIO_REAL = {
    "id": "real",
    "name": "Real-time",
    "kind": "real",
    "description": "Current live planner inputs and runtime state.",
    "read_only": False,
}

SEASON_DEFINITIONS = {
    "winter": {
        "name": "Winter",
        "description": "Short daylight window, higher household demand, and expensive imports.",
        "sunrise": 7.75,
        "sunset": 16.1,
        "solar_peak": 1.0,
        "solar_factors": (0.45, 1.0, 1.35),
        "import_price": 5.2,
        "export_base": 1.1,
        "export_midday": 1.8,
        "export_evening": 2.7,
        "base_load_day": 0.62,
        "base_load_evening": 1.1,
        "base_load_night": 0.48,
        "initial_soc_ratio": 0.38,
    },
    "spring": {
        "name": "Spring",
        "description": "Balanced shoulder-season day with meaningful solar and moderate prices.",
        "sunrise": 6.25,
        "sunset": 19.0,
        "solar_peak": 2.2,
        "solar_factors": (0.6, 1.0, 1.28),
        "import_price": 4.5,
        "export_base": 1.2,
        "export_midday": 2.1,
        "export_evening": 2.4,
        "base_load_day": 0.48,
        "base_load_evening": 0.88,
        "base_load_night": 0.36,
        "initial_soc_ratio": 0.48,
    },
    "summer": {
        "name": "Summer",
        "description": "Long sunny day with strong production and weak midday export economics.",
        "sunrise": 4.9,
        "sunset": 21.2,
        "solar_peak": 3.5,
        "solar_factors": (0.7, 1.0, 1.18),
        "import_price": 4.0,
        "export_base": 0.8,
        "export_midday": 0.25,
        "export_evening": 1.3,
        "base_load_day": 0.34,
        "base_load_evening": 0.56,
        "base_load_night": 0.26,
        "initial_soc_ratio": 0.6,
    },
    "autumn": {
        "name": "Autumn",
        "description": "Falling solar production with valuable evening export and import avoidance.",
        "sunrise": 6.9,
        "sunset": 17.65,
        "solar_peak": 1.55,
        "solar_factors": (0.52, 1.0, 1.25),
        "import_price": 4.8,
        "export_base": 1.0,
        "export_midday": 1.6,
        "export_evening": 3.1,
        "base_load_day": 0.54,
        "base_load_evening": 0.98,
        "base_load_night": 0.4,
        "initial_soc_ratio": 0.44,
    },
}


def scenario_catalog() -> list[dict[str, object]]:
    return [
        SCENARIO_REAL,
        *[
            {
                "id": season_id,
                "name": season["name"],
                "kind": "fake",
                "description": season["description"],
                "read_only": True,
            }
            for season_id, season in SEASON_DEFINITIONS.items()
        ],
    ]


def scenario_metadata(scenario_id: str) -> dict[str, object]:
    for scenario in scenario_catalog():
        if scenario["id"] == scenario_id:
            return scenario
    raise KeyError(scenario_id)


def build_scenario_overrides(config: RuntimeConfig, scenario_id: str, start_at: datetime) -> dict[str, Any]:
    if scenario_id == "real":
        return {}
    season = SEASON_DEFINITIONS.get(scenario_id)
    if season is None:
        raise KeyError(scenario_id)

    bucket_minutes = int(config.scheduler.get("bucket_minutes", 15))
    horizon_buckets = int(config.scheduler.get("horizon_buckets", 192))
    battery = config.assets["battery"]

    import_prices: list[float] = []
    export_prices: list[float] = []
    fixed_load_kwh: list[float] = []

    for bucket in range(horizon_buckets):
        timestamp = start_at + timedelta(minutes=bucket_minutes * bucket)
        hour = timestamp.hour + (timestamp.minute / 60.0)
        import_prices.append(_import_price(hour, season["import_price"]))
        export_prices.append(_export_price(hour, season))
        fixed_load_kwh.append(_base_load(hour, season))

    low, expected, high = season["solar_factors"]
    solar_expected = [_solar_generation(start_at, bucket, bucket_minutes, season, expected) for bucket in range(horizon_buckets)]
    solar_low = [_solar_generation(start_at, bucket, bucket_minutes, season, low) for bucket in range(horizon_buckets)]
    solar_high = [_solar_generation(start_at, bucket, bucket_minutes, season, high) for bucket in range(horizon_buckets)]

    return {
        "forecasts": {
            "prices": {
                "import_czk_per_kwh": import_prices,
                "export_czk_per_kwh": export_prices,
            },
            "solar": {
                "scenarios": [
                    {"id": "solar-low", "probability": 0.25, "generation_kwh": solar_low, "labels": {"kind": "low", "season": scenario_id}},
                    {"id": "solar-expected", "probability": 0.5, "generation_kwh": solar_expected, "labels": {"kind": "expected", "season": scenario_id}},
                    {"id": "solar-high", "probability": 0.25, "generation_kwh": solar_high, "labels": {"kind": "high", "season": scenario_id}},
                ]
            },
        },
        "assets": {
            "battery": {
                "initial_soc_kwh": round(float(battery["capacity_kwh"]) * float(season["initial_soc_ratio"]), 3),
            },
            "base_load": {
                "fixed_demand_kwh": fixed_load_kwh,
            },
        },
    }


def _base_load(hour: float, season: dict[str, Any]) -> float:
    if 6 <= hour < 9:
        value = season["base_load_day"] + 0.08
    elif 17 <= hour < 22:
        value = season["base_load_evening"]
    elif 22 <= hour or hour < 6:
        value = season["base_load_night"]
    else:
        value = season["base_load_day"]
    return round(float(value), 3)


def _import_price(hour: float, base: float) -> float:
    if 0 <= hour < 5:
        return round(base - 0.35, 3)
    if 17 <= hour < 21:
        return round(base + 0.45, 3)
    return round(base, 3)


def _export_price(hour: float, season: dict[str, Any]) -> float:
    if 11 <= hour < 15:
        return round(float(season["export_midday"]), 3)
    if 17 <= hour < 21:
        return round(float(season["export_evening"]), 3)
    return round(float(season["export_base"]), 3)


def _solar_generation(
    start_at: datetime,
    bucket_index: int,
    bucket_minutes: int,
    season: dict[str, Any],
    factor: float,
) -> float:
    timestamp = start_at + timedelta(minutes=bucket_minutes * bucket_index)
    hour = timestamp.hour + (timestamp.minute / 60.0)
    sunrise = float(season["sunrise"])
    sunset = float(season["sunset"])
    if hour <= sunrise or hour >= sunset:
        return 0.0
    daylight_span = sunset - sunrise
    phase = (hour - sunrise) / daylight_span
    curve = math.sin(math.pi * phase)
    generation = float(season["solar_peak"]) * curve**1.55 * factor
    return round(max(0.0, generation), 3)
