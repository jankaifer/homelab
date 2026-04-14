from __future__ import annotations

PRESETS = [
    {
        "id": "high-export-afternoon",
        "name": "High Export Afternoon",
        "description": "Strong afternoon export prices with moderate solar production.",
        "overrides": {
            "forecasts": {
                "prices": {
                    "export_czk_per_kwh": [1.0] * 24 + [4.5] * 12 + [1.0] * 156,
                }
            }
        },
    },
    {
        "id": "low-sun-next-day",
        "name": "Low Sun Next Day",
        "description": "Tomorrow is cloudy, which makes stored energy more valuable.",
        "overrides": {
            "forecasts": {
                "solar": {
                    "scenarios": [
                        {"id": "solar-low", "probability": 0.6, "generation_kwh": [0.0] * 192, "labels": {"kind": "low"}},
                        {"id": "solar-expected", "probability": 0.3, "generation_kwh": [0.0] * 192, "labels": {"kind": "expected"}},
                        {"id": "solar-high", "probability": 0.1, "generation_kwh": [0.0] * 192, "labels": {"kind": "high"}},
                    ]
                }
            }
        },
    },
    {
        "id": "battery-nearly-empty",
        "name": "Battery Nearly Empty",
        "description": "Start the plan with a very low house-battery state of charge.",
        "overrides": {
            "assets": {
                "battery": {
                    "initial_soc_kwh": 1.8,
                }
            }
        },
    },
]
