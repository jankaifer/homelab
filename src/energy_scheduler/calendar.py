from __future__ import annotations

import copy
import json
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from pathlib import Path


DEFAULT_CALENDAR_DAYS = 14
TESLA_CALENDAR_FILENAME = "tesla-calendar.json"


@dataclass
class TeslaDepartureOption:
    active: bool
    confidence: float
    departure_time: str | None
    target_soc_pct: float | None
    source: str


def calendar_path(state_dir: Path) -> Path:
    return state_dir / TESLA_CALENDAR_FILENAME


def _parse_date(value: str) -> date:
    return date.fromisoformat(value)


def _local_now() -> datetime:
    return datetime.now().astimezone()


def _normalize_day(entry: dict[str, object], recurring: dict[str, dict[str, object]]) -> dict[str, object]:
    mode = str(entry.get("mode", "default"))
    entry_date = _parse_date(str(entry["date"]))
    weekday = str(entry_date.weekday())
    default_entry = recurring.get(weekday)
    default_departure = default_entry.get("departure_time") if default_entry else None
    default_target = float(default_entry.get("target_soc_pct")) if default_entry else None
    default_confidence = float(default_entry.get("confidence", 0.35)) if default_entry else 0.0

    if mode == "explicit_departure":
        departure_time = str(entry["departure_time"])
        target_soc_pct = float(entry["target_soc_pct"])
        confidence = 0.9
    elif mode == "no_departure":
        departure_time = default_departure
        target_soc_pct = default_target
        confidence = 0.1 if default_departure is not None and default_target is not None else 0.0
    else:
        mode = "default"
        departure_time = default_departure
        target_soc_pct = default_target
        confidence = default_confidence if default_departure is not None and default_target is not None else 0.0

    return {
        "date": entry_date.isoformat(),
        "mode": mode,
        "departure_time": departure_time,
        "target_soc_pct": target_soc_pct,
        "confidence": confidence,
        "updated_at": entry.get("updated_at"),
    }


def build_default_calendar(recurring_schedule: list[dict[str, object]], days: int = DEFAULT_CALENDAR_DAYS, today: date | None = None) -> dict[str, object]:
    today = today or _local_now().date()
    recurring = {
        str(int(item["weekday"])): {
            "departure_time": item["departure_time"],
            "target_soc_pct": float(item["target_soc_pct"]),
            "confidence": float(item.get("confidence", 0.35)),
        }
        for item in recurring_schedule
    }
    day_entries = []
    for offset in range(days):
        current_date = today + timedelta(days=offset)
        day_entries.append(_normalize_day({"date": current_date.isoformat(), "mode": "default"}, recurring))
    return {"days": day_entries}


def normalize_calendar(calendar: dict[str, object], recurring_schedule: list[dict[str, object]]) -> dict[str, object]:
    recurring = {
        str(int(item["weekday"])): {
            "departure_time": item["departure_time"],
            "target_soc_pct": float(item["target_soc_pct"]),
            "confidence": float(item.get("confidence", 0.35)),
        }
        for item in recurring_schedule
    }
    normalized = []
    seen_dates: set[str] = set()
    for entry in calendar.get("days", []):
        day = _normalize_day(entry, recurring)
        if day["date"] in seen_dates:
            raise ValueError(f"duplicate calendar date '{day['date']}'")
        seen_dates.add(day["date"])
        normalized.append(day)
    normalized.sort(key=lambda item: item["date"])
    return {"days": normalized}


def refresh_calendar_window(
    calendar: dict[str, object],
    recurring_schedule: list[dict[str, object]],
    days: int = DEFAULT_CALENDAR_DAYS,
    today: date | None = None,
) -> dict[str, object]:
    today = today or _local_now().date()
    normalized = normalize_calendar(calendar, recurring_schedule)
    defaults = build_default_calendar(recurring_schedule, days=days, today=today)
    existing_days = {entry["date"]: entry for entry in normalized["days"]}

    merged_days = []
    for default_day in defaults["days"]:
        existing = existing_days.get(default_day["date"])
        if existing is None:
            merged_days.append(default_day)
        elif existing["mode"] == "default":
            merged_days.append(default_day)
        else:
            merged_days.append(existing)
    return normalize_calendar({"days": merged_days}, recurring_schedule)


def load_or_create_calendar(state_dir: Path, recurring_schedule: list[dict[str, object]], persist: bool = True) -> dict[str, object]:
    path = calendar_path(state_dir)
    if path.exists():
        with path.open("r", encoding="utf-8") as handle:
            raw = json.load(handle)
        calendar = refresh_calendar_window(raw, recurring_schedule)
        if persist:
            path.write_text(json.dumps(calendar, indent=2, sort_keys=True), encoding="utf-8")
        return calendar
    calendar = build_default_calendar(recurring_schedule)
    if persist:
        path.write_text(json.dumps(calendar, indent=2, sort_keys=True), encoding="utf-8")
    return calendar


def update_calendar_day(state_dir: Path, recurring_schedule: list[dict[str, object]], day_date: str, payload: dict[str, object]) -> dict[str, object]:
    calendar = load_or_create_calendar(state_dir, recurring_schedule, persist=True)
    days = copy.deepcopy(calendar["days"])
    min_date = _local_now().date()
    max_date = min_date + timedelta(days=DEFAULT_CALENDAR_DAYS - 1)
    target_date = _parse_date(day_date)
    if not (min_date <= target_date <= max_date):
        raise ValueError("date must be within the next 14 days")

    mode = str(payload.get("mode", "default"))
    departure_time = payload.get("departure_time")
    target_soc_pct = payload.get("target_soc_pct")
    if mode == "explicit_departure":
        if departure_time in (None, "") or target_soc_pct is None:
            raise ValueError("explicit_departure requires departure_time and target_soc_pct")
        time.fromisoformat(str(departure_time))
        target_soc_pct = float(target_soc_pct)
        if target_soc_pct < 0 or target_soc_pct > 100:
            raise ValueError("target_soc_pct must be between 0 and 100")
    else:
        if departure_time not in (None, "") or target_soc_pct not in (None, ""):
            raise ValueError("default and no_departure cannot include departure fields")
        departure_time = None
        target_soc_pct = None

    for index, entry in enumerate(days):
        if entry["date"] == day_date:
            days[index] = {
                "date": day_date,
                "mode": mode,
                "departure_time": departure_time,
                "target_soc_pct": target_soc_pct,
                "updated_at": _local_now().isoformat(),
            }
            break
    else:
        raise ValueError("calendar date not found")

    normalized = normalize_calendar({"days": days}, recurring_schedule)
    calendar_path(state_dir).write_text(json.dumps(normalized, indent=2, sort_keys=True), encoding="utf-8")
    return normalized


def build_tesla_scenarios(calendar: dict[str, object], start_at: datetime, horizon_buckets: int, bucket_minutes: int) -> tuple[dict[str, float], dict[str, dict[str, str]], list[dict[str, object]]]:
    relevant_dates = []
    for bucket in range(horizon_buckets):
        bucket_dt = start_at + timedelta(minutes=bucket * bucket_minutes)
        bucket_date = bucket_dt.date().isoformat()
        if bucket_date not in relevant_dates:
            relevant_dates.append(bucket_date)

    relevant_days = [entry for entry in calendar["days"] if entry["date"] in relevant_dates]
    if not relevant_days:
        return {}, {}, calendar["days"]

    scenario_options: list[list[tuple[str, float, dict[str, str]]]] = []
    for entry in relevant_days:
        option_set = []
        if entry["departure_time"] is not None and entry["target_soc_pct"] is not None and entry["confidence"] > 0:
            option_set.append((
                f"{entry['date']}:departure",
                float(entry["confidence"]),
                {
                    "date": entry["date"],
                    "tesla_outcome": "departure",
                    "tesla_mode": str(entry["mode"]),
                    "departure_time": str(entry["departure_time"]),
                    "target_soc_pct": str(entry["target_soc_pct"]),
                },
            ))
        option_set.append((
            f"{entry['date']}:home",
            max(0.0, 1.0 - float(entry["confidence"])),
            {
                "date": entry["date"],
                "tesla_outcome": "home",
                "tesla_mode": str(entry["mode"]),
            },
        ))
        scenario_options.append(option_set)

    scenario_weights: dict[str, float] = {}
    scenario_labels: dict[str, dict[str, str]] = {}

    def _walk(index: int, current_id: list[str], current_probability: float, current_labels: dict[str, str]) -> None:
        if index == len(scenario_options):
            scenario_id = "|".join(current_id) if current_id else "tesla-home"
            scenario_weights[scenario_id] = current_probability
            scenario_labels[scenario_id] = current_labels
            return
        for option_id, probability, labels in scenario_options[index]:
            if probability <= 0:
                continue
            next_labels = dict(current_labels)
            next_labels[f"tesla:{labels['date']}"] = labels["tesla_outcome"]
            if "departure_time" in labels:
                next_labels[f"tesla:{labels['date']}:departure_time"] = labels["departure_time"]
                next_labels[f"tesla:{labels['date']}:target_soc_pct"] = labels["target_soc_pct"]
            next_labels[f"tesla:{labels['date']}:mode"] = labels["tesla_mode"]
            _walk(index + 1, current_id + [option_id], current_probability * probability, next_labels)

    _walk(0, [], 1.0, {})
    total = sum(scenario_weights.values())
    if total > 0:
        scenario_weights = {key: value / total for key, value in scenario_weights.items()}
    return scenario_weights, scenario_labels, calendar["days"]


def option_from_day(entry: dict[str, object]) -> TeslaDepartureOption:
    return TeslaDepartureOption(
        active=entry["departure_time"] is not None and float(entry["confidence"]) > 0,
        confidence=float(entry["confidence"]),
        departure_time=entry["departure_time"],
        target_soc_pct=float(entry["target_soc_pct"]) if entry["target_soc_pct"] is not None else None,
        source=str(entry["mode"]),
    )
