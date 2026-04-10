from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class RuntimeConfig:
    raw: dict[str, Any]
    path: Path

    @property
    def scheduler(self) -> dict[str, Any]:
        return self.raw["scheduler"]

    @property
    def assets(self) -> dict[str, Any]:
        return self.raw["assets"]

    @property
    def forecasts(self) -> dict[str, Any]:
        return self.raw["forecasts"]

    @property
    def runtime(self) -> dict[str, Any]:
        return self.raw.get("runtime", {})


def load_config(path: str | Path) -> RuntimeConfig:
    config_path = Path(path)
    with config_path.open("r", encoding="utf-8") as handle:
        raw = json.load(handle)
    return RuntimeConfig(raw=raw, path=config_path)
