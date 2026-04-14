from __future__ import annotations

import argparse
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from energy_scheduler.calendar import load_or_create_calendar, update_calendar_day
from energy_scheduler.config import RuntimeConfig, load_config
from energy_scheduler.presets import PRESETS
from energy_scheduler.service import SchedulerService


INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Energy Scheduler</title>
  <link rel="stylesheet" href="/styles.css">
</head>
<body>
  <div id="app">
    <header class="hero">
      <div>
        <h1>Energy Scheduler</h1>
        <p>Understand the current plan, inspect Tesla departure confidence, and run a few what-if presets.</p>
      </div>
      <div class="hero-meta">
        <div class="meta-card"><span>Planner</span><strong id="planner-status">Loading…</strong></div>
        <div class="meta-card"><span>Updated</span><strong id="planner-timestamp">—</strong></div>
      </div>
    </header>
    <main class="layout">
      <section class="panel">
        <h2>Current Plan</h2>
        <div class="summary-grid" id="summary-grid"></div>
      </section>
      <section class="panel">
        <h2>Decision Cards</h2>
        <div id="decision-cards" class="cards"></div>
      </section>
      <section class="panel">
        <h2>Expected Timeline</h2>
        <canvas id="timeline-chart" width="960" height="320"></canvas>
      </section>
      <section class="panel">
        <h2>Demand Bands</h2>
        <table id="bands-table">
          <thead><tr><th>Band</th><th>Asset</th><th>Target</th><th>Served</th><th>Shortfall</th><th>Deadline</th><th>Confidence</th></tr></thead>
          <tbody></tbody>
        </table>
      </section>
      <section class="panel">
        <h2>Tesla Planning Calendar</h2>
        <p class="hint">One departure per day. Explicit departures are taken at 90% confidence. “No departure” still leaves a 10% fallback default scenario.</p>
        <table id="calendar-table">
          <thead><tr><th>Date</th><th>Mode</th><th>Departure</th><th>Target SoC</th><th>Confidence</th><th></th></tr></thead>
          <tbody></tbody>
        </table>
      </section>
      <section class="panel">
        <h2>Scenario Presets</h2>
        <div id="preset-list" class="cards"></div>
        <div id="simulation-output" class="simulation-output"></div>
      </section>
    </main>
  </div>
  <script src="/app.js"></script>
</body>
</html>
"""

APP_CSS = """
:root {
  --bg: #eef2e8;
  --panel: #fffef8;
  --ink: #14211b;
  --muted: #5e6d63;
  --accent: #2f6d54;
  --accent-2: #bf6b2c;
  --border: #d7ddcf;
}
body { margin: 0; font-family: Georgia, "Iowan Old Style", serif; background: linear-gradient(180deg, #f5f2e9 0%, var(--bg) 100%); color: var(--ink); }
.hero { display: flex; justify-content: space-between; gap: 2rem; padding: 2rem 2.5rem; background: radial-gradient(circle at top left, rgba(47,109,84,0.18), transparent 45%), transparent; }
.hero h1 { margin: 0 0 0.5rem 0; font-size: 2.4rem; }
.hero p { margin: 0; color: var(--muted); max-width: 52rem; }
.hero-meta { display: flex; gap: 1rem; align-items: flex-start; }
.meta-card, .summary-card, .card, .preset-card { background: var(--panel); border: 1px solid var(--border); border-radius: 18px; box-shadow: 0 8px 28px rgba(20,33,27,0.06); }
.meta-card { padding: 1rem 1.25rem; min-width: 9rem; }
.meta-card span { display:block; color: var(--muted); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.08em; }
.layout { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 1rem; padding: 0 2.5rem 2.5rem; }
.panel { background: rgba(255,255,255,0.55); border: 1px solid rgba(215,221,207,0.9); border-radius: 22px; padding: 1.2rem; backdrop-filter: blur(6px); }
.panel h2 { margin-top: 0; font-size: 1.2rem; }
.summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.75rem; }
.summary-card { padding: 0.95rem; }
.summary-card span { color: var(--muted); display:block; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.06em; }
.summary-card strong { font-size: 1.3rem; }
.cards { display: grid; gap: 0.75rem; }
.card, .preset-card { padding: 1rem; }
.card h3, .preset-card h3 { margin: 0 0 0.4rem 0; font-size: 1rem; }
.card p, .preset-card p, .hint { margin: 0; color: var(--muted); line-height: 1.45; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 0.6rem 0.4rem; border-bottom: 1px solid var(--border); vertical-align: top; }
th { color: var(--muted); font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.08em; }
input, select, button { font: inherit; }
input, select { width: 100%; box-sizing: border-box; padding: 0.45rem 0.55rem; border-radius: 10px; border: 1px solid #c3cbba; background: white; }
button { padding: 0.55rem 0.8rem; border-radius: 999px; border: 0; background: var(--accent); color: white; cursor: pointer; }
button.secondary { background: var(--accent-2); }
.simulation-output { margin-top: 1rem; padding: 1rem; background: #f6f8f3; border-radius: 16px; min-height: 4rem; white-space: pre-wrap; color: var(--muted); }
canvas { width: 100%; height: auto; background: linear-gradient(180deg, rgba(47,109,84,0.08), rgba(191,107,44,0.03)); border-radius: 16px; }
@media (max-width: 760px) {
  .hero, .layout { padding-left: 1rem; padding-right: 1rem; }
  .hero { flex-direction: column; }
}
"""

APP_JS = """
async function fetchJson(path, options = {}) {
  const response = await fetch(path, { headers: { 'Content-Type': 'application/json' }, ...options });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || response.statusText);
  }
  return response.json();
}
function fmt(value, suffix = '') {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'number') return value.toFixed(2) + suffix;
  return String(value);
}
function renderSummary(summary) {
  document.getElementById('planner-status').textContent = summary.planner_status || 'unknown';
  document.getElementById('planner-timestamp').textContent = summary.planner_timestamp || '—';
  const grid = document.getElementById('summary-grid');
  grid.innerHTML = '';
  [
    ['Objective (CZK)', fmt(summary.objective_value_czk)],
    ['Battery SoC (kWh)', fmt(summary.battery_soc_kwh)],
    ['Import Now (kWh)', fmt(summary.current_import_kwh)],
    ['Export Now (kWh)', fmt(summary.current_export_kwh)],
    ['Grid', summary.grid_available ? 'Available' : 'Outage'],
    ['Next Tesla Day', summary.next_tesla_day ? `${summary.next_tesla_day.date} ${summary.next_tesla_day.departure_time || ''}` : 'None'],
  ].forEach(([label, value]) => {
    const card = document.createElement('div');
    card.className = 'summary-card';
    card.innerHTML = `<span>${label}</span><strong>${value}</strong>`;
    grid.appendChild(card);
  });
}
function renderDecisionCards(cards) {
  const container = document.getElementById('decision-cards');
  container.innerHTML = '';
  cards.forEach(card => {
    const div = document.createElement('div');
    div.className = 'card';
    div.innerHTML = `<h3>${card.title}</h3><p>${card.body}</p>`;
    container.appendChild(div);
  });
}
function drawTimelineChart(points) {
  const canvas = document.getElementById('timeline-chart');
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#eef2e8';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  if (!points.length) return;
  const series = [
    { key: 'battery_soc_kwh', color: '#2f6d54' },
    { key: 'solar_kwh', color: '#d08f42' },
    { key: 'import_kwh', color: '#4c6fa8' },
    { key: 'export_kwh', color: '#9a4a22' },
    { key: 'tesla_kwh', color: '#111111' },
  ];
  const maxY = Math.max(1, ...points.flatMap(p => series.map(s => Number(p[s.key] || 0))));
  const pad = 28;
  const width = canvas.width - pad * 2;
  const height = canvas.height - pad * 2;
  ctx.strokeStyle = '#cfd7ca';
  ctx.beginPath();
  for (let i = 0; i <= 4; i++) {
    const y = pad + (height / 4) * i;
    ctx.moveTo(pad, y);
    ctx.lineTo(pad + width, y);
  }
  ctx.stroke();
  series.forEach(seriesItem => {
    ctx.strokeStyle = seriesItem.color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    points.forEach((point, index) => {
      const x = pad + (width * index / Math.max(1, points.length - 1));
      const y = pad + height - ((Number(point[seriesItem.key] || 0) / maxY) * height);
      if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    });
    ctx.stroke();
  });
}
function renderBands(bands) {
  const tbody = document.querySelector('#bands-table tbody');
  tbody.innerHTML = '';
  bands.slice(0, 24).forEach(band => {
    const row = document.createElement('tr');
    row.innerHTML = `
      <td>${band.display_name}</td>
      <td>${band.asset_id}</td>
      <td>${fmt(band.target_quantity_kwh, ' kWh')}</td>
      <td>${fmt(band.served_quantity_kwh, ' kWh')}</td>
      <td>${fmt(band.shortfall_kwh, ' kWh')}</td>
      <td>${band.deadline_index}</td>
      <td>${band.confidence !== null ? `${Math.round(band.confidence * 100)}% (${band.confidence_source})` : '—'}</td>
    `;
    tbody.appendChild(row);
  });
}
async function saveCalendarDay(day, row) {
  const payload = {
    mode: row.querySelector('[data-field="mode"]').value,
    departure_time: row.querySelector('[data-field="departure_time"]').value || null,
    target_soc_pct: row.querySelector('[data-field="target_soc_pct"]').value || null,
  };
  await fetchJson(`/api/tesla/calendar/${day.date}`, { method: 'PUT', body: JSON.stringify(payload) });
  await boot();
}
function renderCalendar(days) {
  const tbody = document.querySelector('#calendar-table tbody');
  tbody.innerHTML = '';
  days.forEach(day => {
    const row = document.createElement('tr');
    row.innerHTML = `
      <td>${day.date}</td>
      <td>
        <select data-field="mode">
          <option value="default" ${day.mode === 'default' ? 'selected' : ''}>default</option>
          <option value="explicit_departure" ${day.mode === 'explicit_departure' ? 'selected' : ''}>explicit_departure</option>
          <option value="no_departure" ${day.mode === 'no_departure' ? 'selected' : ''}>no_departure</option>
        </select>
      </td>
      <td><input data-field="departure_time" type="time" value="${day.departure_time || ''}"></td>
      <td><input data-field="target_soc_pct" type="number" min="0" max="100" value="${day.target_soc_pct ?? ''}"></td>
      <td>${Math.round((day.confidence || 0) * 100)}%</td>
      <td><button>Save</button></td>
    `;
    row.querySelector('button').addEventListener('click', () => saveCalendarDay(day, row));
    tbody.appendChild(row);
  });
}
function renderPresets(presets) {
  const container = document.getElementById('preset-list');
  const output = document.getElementById('simulation-output');
  container.innerHTML = '';
  presets.forEach(preset => {
    const card = document.createElement('div');
    card.className = 'preset-card';
    const button = document.createElement('button');
    button.className = 'secondary';
    button.textContent = 'Run preset';
    button.addEventListener('click', async () => {
      output.textContent = 'Running…';
      const result = await fetchJson(`/api/scenarios/${preset.id}/run`, { method: 'POST', body: '{}' });
      output.textContent = JSON.stringify(result.summary, null, 2);
    });
    card.innerHTML = `<h3>${preset.name}</h3><p>${preset.description}</p>`;
    card.appendChild(button);
    container.appendChild(card);
  });
}
async function boot() {
  const [summaryPayload, bandsPayload, telemetryPayload, calendarPayload, presets] = await Promise.all([
    fetchJson('/api/live/summary'),
    fetchJson('/api/live/bands'),
    fetchJson('/api/live/telemetry'),
    fetchJson('/api/tesla/calendar'),
    fetchJson('/api/scenarios'),
  ]);
  renderSummary(summaryPayload.summary);
  renderDecisionCards(summaryPayload.decision_cards || []);
  drawTimelineChart(telemetryPayload.telemetry_timeline || []);
  renderBands(bandsPayload.bands || []);
  renderCalendar(calendarPayload.days || []);
  renderPresets(presets.presets || []);
}
boot().catch(error => {
  document.getElementById('app').innerHTML = `<div class="panel"><h2>UI Error</h2><p>${error.message}</p></div>`;
});
"""


class UIServer:
    def __init__(self, config: RuntimeConfig):
        self.config = config
        self.scheduler = SchedulerService(config, persist_runtime_state=False)
        self.state_dir = Path(config.runtime.get("state_dir", "/var/lib/energy-scheduler"))

    def latest_plan(self) -> dict[str, object]:
        latest = self.state_dir / "latest-plan.json"
        if not latest.exists():
            return self.scheduler.run_once(persist=False)
        with latest.open("r", encoding="utf-8") as handle:
            return json.load(handle)

    def get_calendar(self) -> dict[str, object]:
        tesla = self.config.assets.get("tesla", {})
        return load_or_create_calendar(self.state_dir, tesla.get("recurring_schedule", []), persist=True)

    def update_calendar(self, day_date: str, payload: dict[str, object]) -> dict[str, object]:
        tesla = self.config.assets.get("tesla", {})
        return update_calendar_day(self.state_dir, tesla.get("recurring_schedule", []), day_date, payload)

    def run_preset(self, preset_id: str) -> dict[str, object]:
        for preset in PRESETS:
            if preset["id"] == preset_id:
                return self.scheduler.simulate(preset["overrides"])
        raise ValueError("unknown preset")


class UIRequestHandler(BaseHTTPRequestHandler):
    server_version = "EnergySchedulerUI/0.1"

    @property
    def ui(self) -> UIServer:
        return self.server.ui_server  # type: ignore[attr-defined]

    def _json(self, payload: dict[str, object], status: int = HTTPStatus.OK) -> None:
        body = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
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

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        try:
            if path == "/":
                self._text(INDEX_HTML, "text/html; charset=utf-8")
            elif path == "/styles.css":
                self._text(APP_CSS, "text/css; charset=utf-8")
            elif path == "/app.js":
                self._text(APP_JS, "application/javascript; charset=utf-8")
            elif path == "/api/live/summary":
                latest = self.ui.latest_plan()
                self._json({"summary": latest["summary"], "decision_cards": latest.get("decision_cards", [])})
            elif path == "/api/live/plan":
                self._json(self.ui.latest_plan())
            elif path == "/api/live/bands":
                self._json({"bands": self.ui.latest_plan().get("bands", [])})
            elif path == "/api/live/telemetry":
                self._json({"telemetry_timeline": self.ui.latest_plan().get("telemetry_timeline", [])})
            elif path == "/api/tesla/calendar":
                self._json(self.ui.get_calendar())
            elif path == "/api/scenarios":
                self._json({"presets": [{"id": preset["id"], "name": preset["name"], "description": preset["description"]} for preset in PRESETS]})
            else:
                self.send_error(HTTPStatus.NOT_FOUND)
        except Exception as exc:  # noqa: BLE001
            self._json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)

    def do_PUT(self) -> None:
        path = urlparse(self.path).path
        if not path.startswith("/api/tesla/calendar/"):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(content_length) or b"{}")
            day_date = path.rsplit("/", 1)[-1]
            self._json(self.ui.update_calendar(day_date, payload))
        except Exception as exc:  # noqa: BLE001
            self._json({"error": str(exc)}, status=HTTPStatus.BAD_REQUEST)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        if not path.startswith("/api/scenarios/") or not path.endswith("/run"):
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            preset_id = path.split("/")[-2]
            self._json(self.ui.run_preset(preset_id))
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
    parser = build_parser()
    args = parser.parse_args()
    config = load_config(args.config)
    ui_server = UIServer(config)
    httpd = ThreadingHTTPServer((args.host, args.port), UIRequestHandler)
    httpd.ui_server = ui_server  # type: ignore[attr-defined]
    httpd.serve_forever()
    return 0
