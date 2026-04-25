from __future__ import annotations

import argparse
import json
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from energy_scheduler.config import RuntimeConfig, load_config
from energy_scheduler.service import SchedulerService


INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Energy Scheduler</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/app.js"></script>
</body>
</html>
"""

UI_STATIC_DIR = Path(__file__).with_name("ui_static")
APP_BUNDLE_PATH = UI_STATIC_DIR / "app.js"


class UIServer:
    def __init__(self, config: RuntimeConfig):
        self.config = config
        self.scheduler = SchedulerService(config, persist_runtime_state=False)
        self.state_dir = Path(config.runtime.get("state_dir", "/var/lib/energy-scheduler"))
        self.history_dir = self.state_dir / "history"

    def latest_plan(self) -> dict[str, object]:
        latest = self.state_dir / "latest-plan.json"
        if not latest.exists():
            return self.scheduler.run_once(persist=False)
        return self._read_json(latest)

    def dashboard(self, selected_date: str | None = None) -> dict[str, object]:
        date_key = selected_date or datetime.now().astimezone().date().isoformat()
        history = self.history_for_date(date_key)
        selected_plan = history[0]["snapshot"] if history else self._latest_for_date(date_key)
        latest = self.latest_plan()
        return {
            "selected_date": date_key,
            "selected_plan": selected_plan,
            "latest_plan": latest,
            "history": history,
            "available_dates": self.available_dates(),
        }

    def history_for_date(self, date_key: str, limit: int = 96) -> list[dict[str, object]]:
        runs = [
            self._history_entry(path)
            for path in self._history_paths()
        ]
        matching = [entry for entry in runs if str(entry.get("date")) == date_key]
        matching.sort(key=lambda entry: str(entry.get("created_at", "")), reverse=True)
        return matching[:limit]

    def available_dates(self, limit: int = 90) -> list[str]:
        dates = {
            str(entry.get("date"))
            for entry in (self._history_entry(path) for path in self._history_paths())
            if entry.get("date")
        }
        latest_date = self._snapshot_date(self.latest_plan())
        if latest_date:
            dates.add(latest_date)
        return sorted(dates, reverse=True)[:limit]

    def _latest_for_date(self, date_key: str) -> dict[str, object] | None:
        latest = self.latest_plan()
        if self._snapshot_date(latest) == date_key:
            return latest
        return None

    def _history_paths(self) -> list[Path]:
        if not self.history_dir.exists():
            return []
        return sorted(self.history_dir.glob("*.json"), reverse=True)

    def _history_entry(self, path: Path) -> dict[str, object]:
        snapshot = self._read_json(path)
        created_at = str(snapshot.get("created_at") or snapshot.get("summary", {}).get("planner_timestamp") or "")
        summary = snapshot.get("summary", {})
        if not isinstance(summary, dict):
            summary = {}
        return {
            "id": path.stem,
            "path": path.name,
            "created_at": created_at,
            "date": self._iso_date(created_at),
            "summary": summary,
            "snapshot": snapshot,
        }

    def _snapshot_date(self, snapshot: dict[str, object]) -> str | None:
        created_at = str(snapshot.get("created_at") or snapshot.get("summary", {}).get("planner_timestamp") or "")
        return self._iso_date(created_at)

    @staticmethod
    def _iso_date(value: str) -> str | None:
        if not value:
            return None
        try:
            return datetime.fromisoformat(value).date().isoformat()
        except ValueError:
            return value[:10] if len(value) >= 10 else None

    @staticmethod
    def _read_json(path: Path) -> dict[str, object]:
        with path.open("r", encoding="utf-8") as handle:
            payload = json.load(handle)
        if not isinstance(payload, dict):
            raise ValueError(f"{path} did not contain a JSON object")
        return payload


class UIRequestHandler(BaseHTTPRequestHandler):
    server_version = "EnergySchedulerUI/0.2"

    @property
    def ui(self) -> UIServer:
        return self.server.ui_server  # type: ignore[attr-defined]

    def _json(self, payload: dict[str, object], status: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, body: str, content_type: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _bytes(self, body: bytes, content_type: str) -> None:
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)
        selected_date = params.get("date", [None])[0]
        try:
            if path in {"/", "/dashboard"}:
                self._text(INDEX_HTML, "text/html; charset=utf-8")
            elif path == "/favicon.ico":
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
            elif path == "/app.js":
                self._bytes(APP_BUNDLE_PATH.read_bytes(), "application/javascript; charset=utf-8")
            elif path == "/api/dashboard":
                self._json(self.ui.dashboard(selected_date))
            elif path == "/api/live/plan":
                self._json(self.ui.latest_plan())
            elif path == "/api/live/summary":
                latest = self.ui.latest_plan()
                self._json({"summary": latest.get("summary", {})})
            elif path == "/api/history/dates":
                self._json({"dates": self.ui.available_dates()})
            elif path == "/api/history":
                date_key = selected_date or datetime.now().astimezone().date().isoformat()
                self._json({"date": date_key, "history": self.ui.history_for_date(date_key)})
            else:
                self.send_error(HTTPStatus.NOT_FOUND)
        except FileNotFoundError as exc:
            self._json({"error": str(exc)}, status=HTTPStatus.NOT_FOUND)
        except Exception as exc:  # noqa: BLE001
            self._json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        return


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the energy scheduler UI service")
    parser.add_argument("--config", required=True, help="Path to the scheduler JSON config")
    parser.add_argument("--port", type=int, default=8787, help="Port to bind the UI service to")
    parser.add_argument("--host", default="127.0.0.1", help="Host address to bind")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    config = load_config(Path(args.config))
    server = ThreadingHTTPServer((args.host, args.port), UIRequestHandler)
    server.ui_server = UIServer(config)  # type: ignore[attr-defined]
    print(f"Energy scheduler UI listening on http://{args.host}:{args.port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
