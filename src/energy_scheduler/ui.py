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
  <div class="app-shell">
    <aside class="sidebar">
      <div class="brand-block">
        <p class="eyebrow">Homelab Energy</p>
        <h1>Energy Scheduler</h1>
        <p class="lede">A clearer view of what the optimizer is planning, why it is doing it, and when the Tesla actually needs to be ready.</p>
      </div>
      <nav class="nav" id="nav-links">
        <a href="/" data-route="overview">Overview</a>
        <a href="/timeline" data-route="timeline">Timeline</a>
        <a href="/tesla" data-route="tesla">Tesla Plan</a>
        <a href="/scenarios" data-route="scenarios">Scenarios</a>
      </nav>
      <div class="status-stack">
        <div class="status-card">
          <span>Planner</span>
          <strong id="planner-status">Loading…</strong>
        </div>
        <div class="status-card">
          <span>Updated</span>
          <strong id="planner-timestamp">—</strong>
        </div>
      </div>
    </aside>

    <main class="main-shell">
      <section class="page active" id="page-overview">
        <header class="page-header">
          <div>
            <p class="eyebrow">Live plan</p>
            <h2>Overview</h2>
          </div>
          <p class="page-copy">Start here. This page answers three questions quickly: what the optimizer expects, what it is prioritizing, and whether tomorrow's Tesla departure is already protected.</p>
        </header>

        <section class="hero-strip">
          <div class="hero-card" id="headline-card"></div>
          <div class="summary-grid" id="summary-grid"></div>
        </section>

        <section class="content-grid">
          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Reasoning</p>
                <h3>Decision Cards</h3>
              </div>
            </div>
            <div class="card-stack" id="decision-cards"></div>
          </article>

          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Near-term commitments</p>
                <h3>Important Bands</h3>
              </div>
            </div>
            <div class="band-stack" id="band-cards"></div>
          </article>
        </section>
      </section>

      <section class="page" id="page-timeline">
        <header class="page-header">
          <div>
            <p class="eyebrow">Expected behavior</p>
            <h2>Timeline</h2>
          </div>
          <p class="page-copy">The first chart shows where energy goes. The second focuses only on the battery so it is easier to read reserve behavior and charge/discharge swings.</p>
        </header>

        <article class="panel panel-chart">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Expected flow</p>
              <h3>Solar, Grid, and Tesla</h3>
            </div>
            <div class="legend" id="flow-legend"></div>
          </div>
          <canvas id="flow-chart" width="1200" height="420"></canvas>
        </article>

        <article class="panel panel-chart">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Storage</p>
              <h3>Battery SoC and Battery Power</h3>
            </div>
            <div class="legend" id="battery-legend"></div>
          </div>
          <canvas id="battery-chart" width="1200" height="360"></canvas>
        </article>
      </section>

      <section class="page" id="page-tesla">
        <header class="page-header">
          <div>
            <p class="eyebrow">Editable</p>
            <h2>Tesla Planning Calendar</h2>
          </div>
          <p class="page-copy">Each day supports one departure. Explicit entries are treated at 90% confidence. “No departure” still leaves a 10% fallback default scenario so the planner is never completely blind.</p>
        </header>

        <section class="content-grid tesla-grid">
          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Summary</p>
                <h3>How confidence works</h3>
              </div>
            </div>
            <div class="confidence-notes" id="tesla-summary"></div>
          </article>

          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Next 14 days</p>
                <h3>Departure Calendar</h3>
              </div>
            </div>
            <div class="calendar-grid" id="calendar-grid"></div>
          </article>
        </section>
      </section>

      <section class="page" id="page-scenarios">
        <header class="page-header">
          <div>
            <p class="eyebrow">Preset experiments</p>
            <h2>Scenarios</h2>
          </div>
          <p class="page-copy">These runs do not change the live planner. Use them to get a feel for tradeoffs before we tune the economics further.</p>
        </header>

        <section class="content-grid">
          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Pick one</p>
                <h3>Scenario Presets</h3>
              </div>
            </div>
            <div class="preset-grid" id="preset-list"></div>
          </article>

          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Simulation output</p>
                <h3>Preset Result</h3>
              </div>
            </div>
            <div id="simulation-empty" class="empty-state">Choose a preset to run a what-if plan.</div>
            <div id="simulation-result" class="simulation-result hidden">
              <div class="summary-grid" id="simulation-summary"></div>
              <div class="card-stack" id="simulation-cards"></div>
              <div class="legend" id="simulation-legend"></div>
              <canvas id="simulation-chart" width="1200" height="340"></canvas>
            </div>
          </article>
        </section>
      </section>
    </main>
  </div>
  <script src="/app.js"></script>
</body>
</html>
"""


APP_CSS = """
:root {
  --bg: #f0ede5;
  --panel: rgba(255, 252, 244, 0.92);
  --panel-solid: #fffaf2;
  --ink: #162018;
  --muted: #5e6b61;
  --accent: #255d49;
  --accent-soft: rgba(37, 93, 73, 0.12);
  --accent-warm: #b96a31;
  --border: #d9d3c6;
  --line-1: #255d49;
  --line-2: #d08b3c;
  --line-3: #4168ad;
  --line-4: #a5481f;
  --line-5: #111111;
  --shadow: 0 18px 40px rgba(22, 32, 24, 0.08);
}
* { box-sizing: border-box; }
html { background: radial-gradient(circle at top left, rgba(37, 93, 73, 0.11), transparent 32%), linear-gradient(180deg, #f8f3e8 0%, var(--bg) 100%); min-height: 100%; }
body {
  margin: 0;
  color: var(--ink);
  font-family: "Avenir Next", "Segoe UI", sans-serif;
  min-height: 100vh;
}
h1, h2, h3 {
  font-family: "Iowan Old Style", "Palatino Linotype", Georgia, serif;
  letter-spacing: -0.02em;
  margin: 0;
}
p { margin: 0; }
.eyebrow {
  margin-bottom: 0.4rem;
  color: var(--muted);
  font-size: 0.78rem;
  text-transform: uppercase;
  letter-spacing: 0.14em;
}
.app-shell {
  display: grid;
  grid-template-columns: 300px minmax(0, 1fr);
  min-height: 100vh;
}
.sidebar {
  padding: 2rem 1.4rem;
  border-right: 1px solid rgba(217, 211, 198, 0.85);
  background: rgba(250, 244, 233, 0.72);
  backdrop-filter: blur(10px);
  position: sticky;
  top: 0;
  height: 100vh;
  display: flex;
  flex-direction: column;
  gap: 1.4rem;
}
.brand-block h1 {
  font-size: 2rem;
  margin-bottom: 0.6rem;
}
.lede {
  color: var(--muted);
  line-height: 1.55;
  font-size: 0.97rem;
}
.nav {
  display: grid;
  gap: 0.45rem;
}
.nav a {
  text-decoration: none;
  color: var(--ink);
  padding: 0.8rem 0.95rem;
  border-radius: 16px;
  font-weight: 600;
  background: transparent;
  border: 1px solid transparent;
  transition: 160ms ease;
}
.nav a:hover,
.nav a.active {
  background: var(--accent-soft);
  border-color: rgba(37, 93, 73, 0.16);
}
.status-stack {
  margin-top: auto;
  display: grid;
  gap: 0.75rem;
}
.status-card,
.hero-card,
.summary-card,
.panel,
.decision-card,
.band-card,
.calendar-card,
.preset-card {
  border: 1px solid var(--border);
  border-radius: 22px;
  background: var(--panel);
  box-shadow: var(--shadow);
}
.status-card,
.summary-card,
.decision-card,
.band-card,
.calendar-card,
.preset-card {
  padding: 1rem;
}
.status-card span,
.summary-card span,
.mini-label {
  color: var(--muted);
  display: block;
  font-size: 0.78rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  margin-bottom: 0.35rem;
}
.status-card strong,
.summary-card strong,
.hero-value {
  font-size: 1.25rem;
}
.main-shell {
  padding: 2rem 2rem 3rem;
  max-width: 1440px;
  width: 100%;
}
.page {
  display: none;
}
.page.active {
  display: grid;
  gap: 1.25rem;
}
.page-header {
  display: flex;
  justify-content: space-between;
  gap: 1.5rem;
  align-items: end;
}
.page-header h2 {
  font-size: 2.25rem;
}
.page-copy {
  max-width: 42rem;
  color: var(--muted);
  line-height: 1.55;
}
.hero-strip {
  display: grid;
  grid-template-columns: 1.25fr 1.75fr;
  gap: 1rem;
}
.hero-card {
  padding: 1.25rem 1.35rem;
  background:
    radial-gradient(circle at top right, rgba(185, 106, 49, 0.15), transparent 34%),
    linear-gradient(135deg, rgba(37, 93, 73, 0.08), rgba(255, 250, 242, 0.92));
}
.hero-card h3 {
  font-size: 1.5rem;
  margin-bottom: 0.45rem;
}
.hero-card p {
  color: var(--muted);
  line-height: 1.55;
}
.summary-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 0.9rem;
}
.content-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1rem;
}
.tesla-grid {
  grid-template-columns: 360px minmax(0, 1fr);
}
.panel {
  padding: 1.15rem;
}
.panel-header {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  align-items: end;
  margin-bottom: 1rem;
}
.panel h3 {
  font-size: 1.3rem;
}
.card-stack,
.band-stack,
.confidence-notes,
.preset-grid,
.calendar-grid {
  display: grid;
  gap: 0.85rem;
}
.decision-card h3,
.band-card h3,
.preset-card h3,
.calendar-card h3 {
  font-size: 1.05rem;
  margin-bottom: 0.45rem;
}
.decision-card p,
.band-card p,
.preset-card p,
.calendar-card p,
.confidence-notes p,
.empty-state {
  color: var(--muted);
  line-height: 1.55;
}
.band-meta,
.calendar-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
  margin-top: 0.85rem;
}
.pill {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  padding: 0.34rem 0.7rem;
  border-radius: 999px;
  background: rgba(37, 93, 73, 0.08);
  color: var(--accent);
  font-size: 0.82rem;
  font-weight: 700;
}
.pill.muted {
  background: rgba(22, 32, 24, 0.06);
  color: var(--muted);
}
.legend {
  display: flex;
  flex-wrap: wrap;
  gap: 0.65rem;
}
.legend-item {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  color: var(--muted);
  font-size: 0.88rem;
}
.legend-dot {
  width: 0.85rem;
  height: 0.85rem;
  border-radius: 999px;
}
.panel-chart canvas,
#simulation-chart {
  width: 100%;
  height: auto;
  border-radius: 18px;
  background: linear-gradient(180deg, rgba(37, 93, 73, 0.06), rgba(255, 250, 242, 0.86));
  border: 1px solid rgba(217, 211, 198, 0.85);
}
.calendar-grid {
  grid-template-columns: repeat(auto-fit, minmax(245px, 1fr));
}
.calendar-card header {
  display: flex;
  justify-content: space-between;
  align-items: start;
  gap: 0.7rem;
  margin-bottom: 0.9rem;
}
.calendar-card .date {
  font-family: "Iowan Old Style", "Palatino Linotype", Georgia, serif;
  font-size: 1.08rem;
}
.field-grid {
  display: grid;
  gap: 0.75rem;
}
.field-row {
  display: grid;
  gap: 0.35rem;
}
.field-row label {
  color: var(--muted);
  font-size: 0.82rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
}
input,
select,
button {
  font: inherit;
}
input,
select {
  width: 100%;
  border: 1px solid #c8cfc2;
  border-radius: 14px;
  padding: 0.7rem 0.8rem;
  background: white;
  color: var(--ink);
}
button {
  border: 0;
  border-radius: 999px;
  background: var(--accent);
  color: white;
  padding: 0.75rem 1rem;
  font-weight: 700;
  cursor: pointer;
}
button.secondary {
  background: var(--accent-warm);
}
button.ghost {
  background: rgba(37, 93, 73, 0.08);
  color: var(--accent);
}
.preset-grid {
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
}
.preset-card {
  display: grid;
  gap: 0.8rem;
  align-content: start;
}
.simulation-result {
  display: grid;
  gap: 1rem;
}
.hidden {
  display: none;
}
.empty-state {
  padding: 1.2rem;
  border-radius: 18px;
  background: rgba(37, 93, 73, 0.05);
}
@media (max-width: 1180px) {
  .app-shell {
    grid-template-columns: 1fr;
  }
  .sidebar {
    position: static;
    height: auto;
    border-right: 0;
    border-bottom: 1px solid rgba(217, 211, 198, 0.85);
  }
  .hero-strip,
  .content-grid,
  .tesla-grid {
    grid-template-columns: 1fr;
  }
}
@media (max-width: 760px) {
  .main-shell {
    padding: 1rem 1rem 2rem;
  }
  .sidebar {
    padding: 1rem;
  }
  .page-header {
    align-items: start;
    flex-direction: column;
  }
  .page-header h2 {
    font-size: 1.8rem;
  }
  .summary-grid {
    grid-template-columns: 1fr 1fr;
  }
  .calendar-grid,
  .preset-grid {
    grid-template-columns: 1fr;
  }
  .nav {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
@media (max-width: 520px) {
  .summary-grid {
    grid-template-columns: 1fr;
  }
  .nav {
    grid-template-columns: 1fr;
  }
}
"""


APP_JS = """
const appState = {
  livePlan: null,
  calendar: null,
  presets: [],
  simulation: null,
};

const ROUTES = {
  "/": "overview",
  "/timeline": "timeline",
  "/tesla": "tesla",
  "/scenarios": "scenarios",
};

const FLOW_SERIES = [
  { key: "solar_kwh", label: "Solar", color: "#d08b3c" },
  { key: "import_kwh", label: "Grid import", color: "#4168ad" },
  { key: "export_kwh", label: "Grid export", color: "#a5481f" },
  { key: "tesla_kwh", label: "Tesla charging", color: "#111111" },
];

const BATTERY_SERIES = [
  { key: "battery_soc_kwh", label: "Battery SoC", color: "#255d49" },
  { key: "battery_charge_kwh", label: "Battery charge", color: "#b96a31" },
  { key: "battery_discharge_kwh", label: "Battery discharge", color: "#4168ad" },
];

function routeName() {
  return ROUTES[window.location.pathname] || "overview";
}

async function fetchJson(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || response.statusText);
  }
  return response.json();
}

function fmt(value, suffix = "") {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") return `${value.toFixed(2)}${suffix}`;
  return String(value);
}

function fmtShort(value, suffix = "") {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") return `${value.toFixed(1)}${suffix}`;
  return String(value);
}

function renderNav() {
  const active = routeName();
  document.querySelectorAll("[data-route]").forEach((link) => {
    link.classList.toggle("active", link.dataset.route === active);
  });
  document.querySelectorAll(".page").forEach((page) => {
    page.classList.toggle("active", page.id === `page-${active}`);
  });
}

function renderStatus(summary) {
  document.getElementById("planner-status").textContent = summary.planner_status || "unknown";
  document.getElementById("planner-timestamp").textContent = summary.planner_timestamp || "—";
}

function renderHeadline(summary) {
  const nextTesla = summary.next_tesla_day;
  const headline = document.getElementById("headline-card");
  headline.innerHTML = `
    <p class="eyebrow">What matters now</p>
    <h3>${summary.current_export_kwh > summary.current_import_kwh ? "Selling energy is currently winning" : "The system is still protecting tomorrow's needs"}</h3>
    <p>${nextTesla ? `Next Tesla planning day: ${nextTesla.date} at ${nextTesla.departure_time || "—"} with ${Math.round((nextTesla.confidence || 0) * 100)}% confidence.` : "No Tesla departure is currently in view for the loaded horizon."}</p>
    <div class="band-meta">
      <span class="pill">${fmtShort(summary.battery_soc_kwh, " kWh")} battery</span>
      <span class="pill muted">${fmtShort(summary.current_import_kwh, " kWh")} importing now</span>
      <span class="pill muted">${fmtShort(summary.current_export_kwh, " kWh")} exporting now</span>
    </div>
  `;
}

function renderSummary(summary) {
  const grid = document.getElementById("summary-grid");
  const items = [
    ["Objective", fmtShort(summary.objective_value_czk, " CZK")],
    ["Battery SoC", fmtShort(summary.battery_soc_kwh, " kWh")],
    ["Grid import", fmtShort(summary.current_import_kwh, " kWh")],
    ["Grid export", fmtShort(summary.current_export_kwh, " kWh")],
    ["Bucket size", `${summary.bucket_minutes} min`],
    ["Horizon", `${summary.horizon_buckets} buckets`],
  ];
  grid.innerHTML = items.map(([label, value]) => `
    <div class="summary-card">
      <span>${label}</span>
      <strong>${value}</strong>
    </div>
  `).join("");
}

function renderDecisionCards(cards, targetId = "decision-cards") {
  const container = document.getElementById(targetId);
  container.innerHTML = cards.map((card) => `
    <article class="decision-card">
      <h3>${card.title}</h3>
      <p>${card.body}</p>
    </article>
  `).join("");
}

function renderBandCards(bands) {
  const important = [...bands]
    .sort((a, b) => {
      const requiredDelta = Number(b.required_level) - Number(a.required_level);
      if (requiredDelta !== 0) return requiredDelta;
      return a.deadline_index - b.deadline_index;
    })
    .slice(0, 8);
  const container = document.getElementById("band-cards");
  container.innerHTML = important.map((band) => `
    <article class="band-card">
      <h3>${band.display_name}</h3>
      <p>${band.required_level ? "Required band" : "Opportunistic band"} for ${band.asset_id}. Target ${fmtShort(band.target_quantity_kwh, " kWh")} by bucket ${band.deadline_index}.</p>
      <div class="band-meta">
        <span class="pill">${fmtShort(band.served_quantity_kwh, " kWh")} served</span>
        <span class="pill ${band.shortfall_kwh > 0.01 ? "" : "muted"}">${fmtShort(band.shortfall_kwh, " kWh")} shortfall</span>
        <span class="pill muted">${band.confidence !== null ? `${Math.round(band.confidence * 100)}% ${band.confidence_source}` : "no confidence"}</span>
      </div>
    </article>
  `).join("");
}

function renderLegend(targetId, series) {
  const target = document.getElementById(targetId);
  target.innerHTML = series.map((item) => `
    <span class="legend-item"><span class="legend-dot" style="background:${item.color}"></span>${item.label}</span>
  `).join("");
}

function drawChart(canvasId, points, series, bucketMinutes, opts = {}) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  const { width, height } = canvas;
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#fffaf2";
  ctx.fillRect(0, 0, width, height);
  if (!points.length) return;

  const padLeft = 66;
  const padRight = 18;
  const padTop = 18;
  const padBottom = 40;
  const plotWidth = width - padLeft - padRight;
  const plotHeight = height - padTop - padBottom;
  const maxY = Math.max(1, ...points.flatMap((point) => series.map((item) => Number(point[item.key] || 0))));

  ctx.strokeStyle = "#d9d3c6";
  ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i += 1) {
    const y = padTop + (plotHeight / 4) * i;
    ctx.beginPath();
    ctx.moveTo(padLeft, y);
    ctx.lineTo(padLeft + plotWidth, y);
    ctx.stroke();
    const labelValue = ((maxY * (4 - i)) / 4).toFixed(1);
    ctx.fillStyle = "#5e6b61";
    ctx.font = "12px Avenir Next";
    ctx.fillText(labelValue, 14, y + 4);
  }

  const labelHours = (index) => {
    const hours = (index * bucketMinutes) / 60;
    return `+${hours.toFixed(hours >= 10 ? 0 : 1)}h`;
  };
  const tickIndexes = [0, Math.floor(points.length * 0.25), Math.floor(points.length * 0.5), Math.floor(points.length * 0.75), points.length - 1]
    .filter((value, index, self) => self.indexOf(value) === index);

  tickIndexes.forEach((idx) => {
    const x = padLeft + (plotWidth * idx / Math.max(1, points.length - 1));
    ctx.strokeStyle = "rgba(217, 211, 198, 0.6)";
    ctx.beginPath();
    ctx.moveTo(x, padTop);
    ctx.lineTo(x, padTop + plotHeight);
    ctx.stroke();
    ctx.fillStyle = "#5e6b61";
    ctx.font = "12px Avenir Next";
    ctx.fillText(labelHours(idx), x - 14, height - 14);
  });

  series.forEach((item) => {
    ctx.strokeStyle = item.color;
    ctx.lineWidth = item.width || 3;
    ctx.beginPath();
    points.forEach((point, index) => {
      const value = Number(point[item.key] || 0);
      const x = padLeft + (plotWidth * index / Math.max(1, points.length - 1));
      const y = padTop + plotHeight - ((value / maxY) * plotHeight);
      if (index === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();
  });

  if (opts.title) {
    ctx.fillStyle = "#162018";
    ctx.font = "600 14px Avenir Next";
    ctx.fillText(opts.title, padLeft, 14);
  }
}

function renderTeslaSummary(days) {
  const nextExplicit = days.find((day) => day.mode === "explicit_departure");
  const nextFallback = days.find((day) => day.mode === "no_departure");
  document.getElementById("tesla-summary").innerHTML = `
    <p><strong>Default days</strong> use the recurring weekday pattern with low confidence. They are meant as a hint, not a promise.</p>
    <p><strong>Explicit departure days</strong> override the default schedule and are taken at 90% confidence.</p>
    <p><strong>No departure days</strong> still keep a 10% fallback default scenario, so the planner stays a little conservative.</p>
    <div class="band-meta">
      <span class="pill">${nextExplicit ? `Next explicit: ${nextExplicit.date}` : "No explicit departures yet"}</span>
      <span class="pill muted">${nextFallback ? `No-departure fallback set on ${nextFallback.date}` : "No no-departure overrides"}</span>
    </div>
  `;
}

async function saveCalendarDay(day, card) {
  const payload = {
    mode: card.querySelector('[data-field="mode"]').value,
    departure_time: card.querySelector('[data-field="departure_time"]').value || null,
    target_soc_pct: card.querySelector('[data-field="target_soc_pct"]').value || null,
  };
  await fetchJson(`/api/tesla/calendar/${day.date}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });
  await boot();
}

function renderCalendar(days) {
  const container = document.getElementById("calendar-grid");
  container.innerHTML = "";
  days.forEach((day) => {
    const card = document.createElement("article");
    card.className = "calendar-card";
    card.innerHTML = `
      <header>
        <div>
          <span class="mini-label">Date</span>
          <div class="date">${day.date}</div>
        </div>
        <span class="pill ${day.mode === "explicit_departure" ? "" : "muted"}">${Math.round((day.confidence || 0) * 100)}%</span>
      </header>
      <div class="field-grid">
        <div class="field-row">
          <label>Mode</label>
          <select data-field="mode">
            <option value="default" ${day.mode === "default" ? "selected" : ""}>Default schedule</option>
            <option value="explicit_departure" ${day.mode === "explicit_departure" ? "selected" : ""}>Explicit departure</option>
            <option value="no_departure" ${day.mode === "no_departure" ? "selected" : ""}>No departure</option>
          </select>
        </div>
        <div class="field-row">
          <label>Departure time</label>
          <input data-field="departure_time" type="time" value="${day.departure_time || ""}">
        </div>
        <div class="field-row">
          <label>Target SoC</label>
          <input data-field="target_soc_pct" type="number" min="0" max="100" value="${day.target_soc_pct ?? ""}">
        </div>
        <button class="ghost">Save day</button>
      </div>
    `;
    card.querySelector("button").addEventListener("click", () => saveCalendarDay(day, card));
    container.appendChild(card);
  });
  renderTeslaSummary(days);
}

function renderPresetCards(presets) {
  const container = document.getElementById("preset-list");
  container.innerHTML = "";
  presets.forEach((preset) => {
    const card = document.createElement("article");
    card.className = "preset-card";
    card.innerHTML = `
      <div>
        <span class="mini-label">Preset</span>
        <h3>${preset.name}</h3>
      </div>
      <p>${preset.description}</p>
      <button class="secondary">Run preset</button>
    `;
    card.querySelector("button").addEventListener("click", () => runPreset(preset.id));
    container.appendChild(card);
  });
}

function renderSimulation(result) {
  const empty = document.getElementById("simulation-empty");
  const panel = document.getElementById("simulation-result");
  if (!result) {
    empty.classList.remove("hidden");
    panel.classList.add("hidden");
    return;
  }
  empty.classList.add("hidden");
  panel.classList.remove("hidden");

  const summaryGrid = document.getElementById("simulation-summary");
  summaryGrid.innerHTML = [
    ["Objective", fmtShort(result.summary.objective_value_czk, " CZK")],
    ["Battery SoC", fmtShort(result.summary.battery_soc_kwh, " kWh")],
    ["Grid import", fmtShort(result.summary.current_import_kwh, " kWh")],
    ["Grid export", fmtShort(result.summary.current_export_kwh, " kWh")],
  ].map(([label, value]) => `
    <div class="summary-card">
      <span>${label}</span>
      <strong>${value}</strong>
    </div>
  `).join("");

  renderDecisionCards(result.decision_cards || [], "simulation-cards");
  renderLegend("simulation-legend", FLOW_SERIES);
  drawChart(
    "simulation-chart",
    result.telemetry_timeline || [],
    FLOW_SERIES,
    result.summary.bucket_minutes || 15,
    { title: "Preset energy flow" },
  );
}

async function runPreset(presetId) {
  const result = await fetchJson(`/api/scenarios/${presetId}/run`, {
    method: "POST",
    body: "{}",
  });
  appState.simulation = result;
  renderSimulation(appState.simulation);
}

function renderLivePlan() {
  const livePlan = appState.livePlan;
  const summary = livePlan.summary || {};
  renderStatus(summary);
  renderHeadline(summary);
  renderSummary(summary);
  renderDecisionCards(livePlan.decision_cards || []);
  renderBandCards(livePlan.bands || []);
  renderLegend("flow-legend", FLOW_SERIES);
  renderLegend("battery-legend", BATTERY_SERIES);
  drawChart("flow-chart", livePlan.telemetry_timeline || [], FLOW_SERIES, summary.bucket_minutes || 15, { title: "Expected energy flow" });
  drawChart("battery-chart", livePlan.telemetry_timeline || [], BATTERY_SERIES, summary.bucket_minutes || 15, { title: "Expected battery behavior" });
}

async function boot() {
  const [livePlan, calendar, presets] = await Promise.all([
    fetchJson("/api/live/plan"),
    fetchJson("/api/tesla/calendar"),
    fetchJson("/api/scenarios"),
  ]);
  appState.livePlan = livePlan;
  appState.calendar = calendar;
  appState.presets = presets.presets || [];
  renderNav();
  renderLivePlan();
  renderCalendar(appState.calendar.days || []);
  renderPresetCards(appState.presets);
  renderSimulation(appState.simulation);
}

function handleNavigation(event) {
  const link = event.target.closest("[data-route]");
  if (!link) return;
  event.preventDefault();
  history.pushState({}, "", link.getAttribute("href"));
  renderNav();
}

document.addEventListener("click", handleNavigation);
window.addEventListener("popstate", renderNav);

boot().catch((error) => {
  document.body.innerHTML = `<main class="main-shell"><section class="panel"><h2>UI Error</h2><p>${error.message}</p></section></main>`;
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
            if path in {"/", "/timeline", "/tesla", "/scenarios"}:
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
                self._json({
                    "presets": [
                        {"id": preset["id"], "name": preset["name"], "description": preset["description"]}
                        for preset in PRESETS
                    ]
                })
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


if __name__ == "__main__":
    raise SystemExit(main())
