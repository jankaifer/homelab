from __future__ import annotations

import argparse
import json
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from energy_scheduler.calendar import load_or_create_calendar, update_calendar_day
from energy_scheduler.config import RuntimeConfig, load_config
from energy_scheduler.scenario_catalog import build_scenario_overrides, scenario_catalog, scenario_metadata
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
      </nav>
      <section class="source-card">
        <p class="eyebrow">Plan Source</p>
        <div class="field-row">
          <label for="scenario-select">Scenario</label>
          <select id="scenario-select"></select>
        </div>
        <p class="source-copy" id="scenario-description">Loading scenario sources…</p>
        <div class="band-meta">
          <span class="pill muted" id="scenario-kind-pill">—</span>
        </div>
      </section>
      <div class="status-stack">
        <div class="status-card">
          <span>Source</span>
          <strong id="scenario-status">—</strong>
        </div>
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
      <section class="source-banner hidden" id="source-banner"></section>
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

        <section class="content-grid single-column">
          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Near-term priorities</p>
                <h3>What The Planner Is Prioritizing</h3>
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
          <p class="page-copy">These charts show the next part of the planning horizon, up to 24 hours, and they are aggregated to one-hour steps. The first chart balances sources against uses. The second shows how much battery state the optimizer wants to carry forward.</p>
        </header>

        <article class="panel panel-chart">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Balance</p>
              <h3>Hourly Energy Balance</h3>
            </div>
            <div class="legend" id="flow-legend"></div>
          </div>
          <div class="chart-metrics" id="flow-metrics"></div>
          <div class="chart-frame" id="flow-chart"></div>
          <p class="chart-note">Above zero = energy sources. Below zero = energy uses. If the chart is honest, every hour balances.</p>
        </article>

        <article class="panel panel-chart">
          <div class="panel-header">
            <div>
              <p class="eyebrow">Storage</p>
              <h3>Battery State Of Charge</h3>
            </div>
            <div class="legend" id="battery-legend"></div>
          </div>
          <div class="chart-metrics" id="battery-metrics"></div>
          <div class="chart-frame" id="battery-chart"></div>
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
                <h3>How The Tesla Hint Works</h3>
              </div>
            </div>
            <div class="confidence-notes" id="tesla-summary"></div>
          </article>

          <article class="panel panel-chart">
            <div class="panel-header">
              <div>
              <p class="eyebrow">Next 24 hours</p>
              <h3>Planned Tesla Charging</h3>
            </div>
            <div class="legend" id="tesla-legend"></div>
          </div>
          <div class="chart-metrics" id="tesla-metrics"></div>
          <div class="chart-frame" id="tesla-chart"></div>
        </article>
        </section>

        <section class="content-grid single-column">
          <article class="panel">
            <div class="panel-header">
              <div>
                <p class="eyebrow">Next 14 days</p>
                <h3>Departure Calendar</h3>
              </div>
            </div>
            <div class="calendar-notice hidden" id="calendar-readonly-note"></div>
            <div class="calendar-shell">
              <div class="calendar-weekdays">
                <span>Mon</span>
                <span>Tue</span>
                <span>Wed</span>
                <span>Thu</span>
                <span>Fri</span>
                <span>Sat</span>
                <span>Sun</span>
              </div>
              <div class="calendar-grid" id="calendar-grid"></div>
            </div>
          </article>
        </section>
      </section>
    </main>
  </div>
  <dialog class="calendar-modal" id="calendar-modal">
    <form class="modal-card" id="calendar-modal-form" method="dialog">
      <div class="modal-header">
        <div>
          <p class="eyebrow">Tesla day setup</p>
          <h3 id="calendar-modal-title">Edit day</h3>
        </div>
        <button type="button" class="modal-close" id="calendar-modal-close" aria-label="Close">×</button>
      </div>
      <p class="modal-copy" id="calendar-modal-copy"></p>
      <div class="mode-picker" id="calendar-mode-picker">
        <label class="mode-choice">
          <input type="radio" name="mode" value="default">
          <span>
            <strong>Default</strong>
            <small>Use the recurring low-confidence schedule.</small>
          </span>
        </label>
        <label class="mode-choice">
          <input type="radio" name="mode" value="explicit_departure">
          <span>
            <strong>Departure</strong>
            <small>Set a real departure with 90% confidence.</small>
          </span>
        </label>
        <label class="mode-choice">
          <input type="radio" name="mode" value="no_departure">
          <span>
            <strong>No departure</strong>
            <small>Tell the planner the car probably stays home.</small>
          </span>
        </label>
      </div>
      <div class="field-grid modal-fields">
        <div class="field-row">
          <label>Departure time</label>
          <input id="calendar-modal-time" type="time">
        </div>
        <div class="field-row">
          <label>Target SoC</label>
          <input id="calendar-modal-soc" type="number" min="0" max="100">
        </div>
      </div>
      <div class="modal-actions">
        <button type="button" class="ghost" id="calendar-modal-cancel">Cancel</button>
        <button type="submit">Save day</button>
      </div>
    </form>
  </dialog>
  <script src="/app.js"></script>
</body>
</html>
"""


APP_CSS = """
:root {
  --bg: #f3efe7;
  --panel: rgba(255, 252, 246, 0.94);
  --ink: #152119;
  --muted: #617166;
  --accent: #255d49;
  --accent-soft: rgba(37, 93, 73, 0.11);
  --accent-warm: #b96a31;
  --accent-danger: #a5481f;
  --accent-blue: #4168ad;
  --border: #d8d1c2;
  --shadow: 0 18px 42px rgba(21, 33, 25, 0.08);
}
* { box-sizing: border-box; }
html { background: radial-gradient(circle at top left, rgba(37, 93, 73, 0.11), transparent 30%), linear-gradient(180deg, #fbf7ee 0%, var(--bg) 100%); min-height: 100%; }
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
  grid-template-columns: 290px minmax(0, 1fr);
  min-height: 100vh;
}
.sidebar {
  padding: 2rem 1.4rem;
  border-right: 1px solid rgba(216, 209, 194, 0.9);
  background: rgba(249, 244, 234, 0.76);
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
.source-card {
  display: grid;
  gap: 0.75rem;
  border: 1px solid var(--border);
  border-radius: 22px;
  background: var(--panel);
  box-shadow: var(--shadow);
  padding: 1rem;
}
.source-card .field-row {
  gap: 0.25rem;
}
.source-card .band-meta {
  margin-top: 0;
}
.source-copy {
  color: var(--muted);
  line-height: 1.45;
  font-size: 0.92rem;
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
.band-card,
.calendar-card {
  border: 1px solid var(--border);
  border-radius: 22px;
  background: var(--panel);
  box-shadow: var(--shadow);
}
.status-card,
.summary-card,
.band-card,
.calendar-card {
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
  min-width: 0;
}
.page {
  display: none;
}
.page.active {
  display: grid;
  gap: 1.15rem;
}
.source-banner {
  padding: 1rem 1.15rem;
  border: 1px solid rgba(37, 93, 73, 0.16);
  border-radius: 20px;
  background: linear-gradient(135deg, rgba(37, 93, 73, 0.08), rgba(255, 252, 246, 0.92));
  color: var(--muted);
  line-height: 1.5;
}
.source-banner strong {
  color: var(--ink);
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
  grid-template-columns: minmax(0, 1.05fr) minmax(0, 1.95fr);
  gap: 1rem;
}
.hero-card {
  padding: 1.35rem 1.45rem;
  background:
    radial-gradient(circle at top right, rgba(185, 106, 49, 0.15), transparent 34%),
    linear-gradient(135deg, rgba(37, 93, 73, 0.08), rgba(255, 250, 242, 0.92));
}
.hero-card h3 {
  font-size: 1.6rem;
  margin-bottom: 0.5rem;
}
.hero-card p {
  color: var(--muted);
  line-height: 1.55;
}
.summary-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
  gap: 0.9rem;
}
.content-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 1rem;
  align-items: start;
}
.single-column {
  grid-template-columns: 1fr;
}
.tesla-grid {
  grid-template-columns: 360px minmax(0, 1fr);
}
.panel {
  padding: 1.15rem;
  min-width: 0;
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
.band-stack,
.confidence-notes,
.calendar-grid {
  display: grid;
  gap: 0.85rem;
}
.band-card h3,
.calendar-card h3 {
  font-size: 1.05rem;
  margin-bottom: 0.35rem;
}
.band-card p,
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
  margin-top: 0.8rem;
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
.pill.warning {
  background: rgba(165, 72, 31, 0.12);
  color: var(--accent-danger);
}
.pill.ok {
  background: rgba(37, 93, 73, 0.12);
  color: var(--accent);
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
.chart-metrics {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 0.75rem;
  margin-bottom: 0.9rem;
}
.metric-card {
  padding: 0.8rem 0.9rem;
  border-radius: 18px;
  border: 1px solid rgba(216, 209, 194, 0.9);
  background: linear-gradient(180deg, rgba(255, 255, 255, 0.92), rgba(245, 240, 232, 0.9));
}
.metric-label {
  display: block;
  color: var(--muted);
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.1em;
  margin-bottom: 0.35rem;
}
.metric-value {
  display: block;
  font-size: 1.12rem;
  font-weight: 700;
  line-height: 1.15;
}
.metric-foot {
  display: block;
  margin-top: 0.28rem;
  color: var(--muted);
  font-size: 0.82rem;
  line-height: 1.35;
}
.metric-card.warning .metric-value,
.metric-card.warning .metric-foot {
  color: var(--accent-danger);
}
.metric-card.ok .metric-value {
  color: var(--accent);
}
.chart-frame {
  position: relative;
  width: 100%;
  min-height: 360px;
  border-radius: 20px;
  background:
    linear-gradient(180deg, rgba(37, 93, 73, 0.08), rgba(255, 250, 242, 0.95)),
    linear-gradient(90deg, rgba(37, 93, 73, 0.02), rgba(255, 255, 255, 0));
  border: 1px solid rgba(217, 211, 198, 0.92);
  overflow: hidden;
}
.chart-frame svg {
  display: block;
  width: 100%;
  height: auto;
  cursor: crosshair;
}
.chart-note {
  margin-top: 0.8rem;
  color: var(--muted);
  line-height: 1.55;
}
.axis-label,
.chart-empty {
  fill: var(--muted);
  font: 12px "Avenir Next", "Segoe UI", sans-serif;
}
.chart-title {
  fill: var(--ink);
  font: 600 14px "Avenir Next", "Segoe UI", sans-serif;
}
.chart-grid {
  stroke: rgba(216, 209, 194, 0.9);
  stroke-width: 1;
}
.chart-axis {
  stroke: rgba(97, 113, 102, 0.9);
  stroke-width: 1.2;
}
.chart-hover-band {
  fill: rgba(37, 93, 73, 0.08);
  opacity: 0;
}
.chart-hover-line {
  stroke: rgba(37, 93, 73, 0.55);
  stroke-dasharray: 5 5;
  stroke-width: 1.5;
  opacity: 0;
}
.chart-hover-dot {
  fill: var(--accent);
  stroke: rgba(255, 252, 246, 0.98);
  stroke-width: 3;
  opacity: 0;
}
.chart-line-primary {
  fill: none;
  stroke: var(--accent);
  stroke-width: 3.2;
}
.chart-line-secondary {
  fill: none;
  stroke: var(--accent-warm);
  stroke-width: 2.4;
  stroke-dasharray: 7 5;
}
.chart-line-danger {
  fill: none;
  stroke: var(--accent-danger);
  stroke-width: 2.4;
  stroke-dasharray: 4 5;
}
.chart-area {
  fill: rgba(37, 93, 73, 0.14);
}
.chart-tooltip {
  position: absolute;
  left: 0;
  top: 0;
  z-index: 3;
  min-width: 220px;
  max-width: 320px;
  padding: 0.85rem 0.95rem;
  border-radius: 16px;
  border: 1px solid rgba(216, 209, 194, 0.92);
  background: rgba(255, 252, 246, 0.98);
  box-shadow: 0 18px 44px rgba(21, 33, 25, 0.16);
  pointer-events: none;
  opacity: 0;
  transform: translate(-50%, calc(-100% - 14px));
  transition: opacity 120ms ease;
}
.chart-tooltip.visible {
  opacity: 1;
}
.chart-tooltip h4 {
  margin: 0 0 0.6rem;
  font-size: 0.98rem;
}
.chart-tooltip-list {
  display: grid;
  gap: 0.38rem;
}
.chart-tooltip-row {
  display: flex;
  justify-content: space-between;
  gap: 0.8rem;
  align-items: center;
  font-size: 0.88rem;
}
.chart-tooltip-key {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  color: var(--muted);
}
.chart-tooltip-value {
  font-weight: 700;
}
.chart-tooltip-swatch {
  width: 0.72rem;
  height: 0.72rem;
  border-radius: 999px;
  flex: 0 0 auto;
}
.chart-tooltip-foot {
  margin-top: 0.7rem;
  padding-top: 0.6rem;
  border-top: 1px solid rgba(216, 209, 194, 0.86);
  color: var(--muted);
  font-size: 0.82rem;
  line-height: 1.45;
}
.calendar-grid {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 0.75rem;
}
.calendar-notice {
  margin-bottom: 0.85rem;
  padding: 0.85rem 0.95rem;
  border-radius: 16px;
  border: 1px solid rgba(216, 209, 194, 0.92);
  background: rgba(37, 93, 73, 0.06);
  color: var(--muted);
  line-height: 1.5;
}
.calendar-shell {
  display: grid;
  gap: 0.75rem;
}
.calendar-weekdays {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 0.75rem;
}
.calendar-weekdays span {
  color: var(--muted);
  font-size: 0.8rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  padding: 0 0.25rem;
}
.calendar-blank {
  min-height: 150px;
}
.calendar-day {
  min-height: 150px;
  padding: 0.95rem;
  text-align: left;
  display: grid;
  gap: 0.7rem;
  align-content: start;
  border: 1px solid var(--border);
  border-radius: 22px;
  background: var(--panel);
  box-shadow: var(--shadow);
}
.calendar-day:hover {
  border-color: rgba(37, 93, 73, 0.35);
  background: rgba(255, 252, 246, 0.98);
}
.calendar-day:disabled {
  cursor: default;
}
.calendar-day:disabled:hover {
  border-color: var(--border);
}
.calendar-day.today {
  outline: 2px solid rgba(37, 93, 73, 0.22);
}
.calendar-day.explicit {
  background: linear-gradient(180deg, rgba(37, 93, 73, 0.1), rgba(255, 252, 246, 0.97));
}
.calendar-day.no-departure {
  background: linear-gradient(180deg, rgba(165, 72, 31, 0.08), rgba(255, 252, 246, 0.97));
}
.calendar-day-header {
  display: flex;
  justify-content: space-between;
  gap: 0.6rem;
  align-items: start;
}
.calendar-day-number {
  font-family: "Iowan Old Style", "Palatino Linotype", Georgia, serif;
  font-size: 1.35rem;
  line-height: 1;
}
.calendar-day-label {
  color: var(--muted);
  font-size: 0.86rem;
}
.calendar-day-body {
  display: grid;
  gap: 0.45rem;
}
.calendar-day-body strong {
  font-size: 1rem;
}
.calendar-day-body p {
  color: var(--muted);
  font-size: 0.9rem;
  line-height: 1.45;
}
.calendar-day-footer {
  margin-top: auto;
}
.calendar-modal {
  width: min(560px, calc(100vw - 2rem));
  padding: 0;
  border: 0;
  border-radius: 28px;
  background: transparent;
  box-shadow: none;
}
.calendar-modal::backdrop {
  background: rgba(15, 23, 18, 0.45);
  backdrop-filter: blur(6px);
}
.modal-card {
  display: grid;
  gap: 1rem;
  padding: 1.4rem;
  border: 1px solid var(--border);
  border-radius: 28px;
  background: var(--panel);
  box-shadow: 0 28px 60px rgba(21, 33, 25, 0.18);
}
.modal-header {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  align-items: start;
}
.modal-copy {
  color: var(--muted);
  line-height: 1.55;
}
.modal-close {
  width: 40px;
  height: 40px;
  border-radius: 999px;
  background: rgba(37, 93, 73, 0.08);
  color: var(--accent);
  padding: 0;
  font-size: 1.4rem;
  line-height: 1;
}
.mode-picker {
  display: grid;
  gap: 0.7rem;
}
.mode-choice {
  display: grid;
  grid-template-columns: 20px minmax(0, 1fr);
  gap: 0.8rem;
  align-items: start;
  padding: 0.9rem 1rem;
  border: 1px solid var(--border);
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.72);
}
.mode-choice:has(input:checked) {
  border-color: rgba(37, 93, 73, 0.36);
  background: rgba(37, 93, 73, 0.08);
}
.mode-choice strong {
  display: block;
  margin-bottom: 0.2rem;
}
.mode-choice small {
  color: var(--muted);
  line-height: 1.45;
}
.mode-choice input {
  margin-top: 0.2rem;
}
.modal-fields {
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
.modal-actions {
  display: flex;
  justify-content: end;
  gap: 0.7rem;
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
input:disabled {
  color: #9ba59d;
  background: #f4f2ec;
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
.hidden {
  display: none;
}
.empty-state {
  padding: 1.2rem;
  border-radius: 18px;
  background: rgba(37, 93, 73, 0.05);
}
.band-card {
  display: grid;
  gap: 0.7rem;
}
.band-topline {
  display: flex;
  justify-content: space-between;
  gap: 0.75rem;
  align-items: start;
}
.band-copy {
  color: var(--muted);
  line-height: 1.55;
}
.meter {
  height: 10px;
  border-radius: 999px;
  background: rgba(37, 93, 73, 0.08);
  overflow: hidden;
}
.meter > span {
  display: block;
  height: 100%;
  border-radius: inherit;
  background: linear-gradient(90deg, var(--accent), #3d8267);
}
.meter.warning > span {
  background: linear-gradient(90deg, var(--accent-warm), var(--accent-danger));
}
.band-stats {
  display: flex;
  justify-content: space-between;
  gap: 0.75rem;
  align-items: center;
}
.band-stats strong {
  font-size: 1rem;
}
.band-stats span {
  color: var(--muted);
  font-size: 0.92rem;
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
    gap: 1rem;
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
    padding: 0.95rem 1rem 1rem;
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
  .brand-block h1 {
    font-size: 2.15rem;
  }
  .lede {
    max-width: 32rem;
    font-size: 0.95rem;
    line-height: 1.45;
  }
  .status-stack {
    margin-top: 0;
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
  .status-card {
    padding: 0.9rem 1rem;
  }
  .nav { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .nav a {
    text-align: center;
  }
  .chart-frame { min-height: 280px; }
  .chart-metrics {
    grid-template-columns: 1fr 1fr;
    gap: 0.6rem;
  }
  .metric-card {
    padding: 0.7rem 0.75rem;
  }
  .metric-value {
    font-size: 1rem;
  }
  .calendar-shell {
    gap: 0.55rem;
  }
  .calendar-weekdays {
    gap: 0.45rem;
  }
  .calendar-grid {
    gap: 0.45rem;
  }
  .calendar-day,
  .calendar-blank {
    min-height: 120px;
  }
  .calendar-day {
    padding: 0.65rem;
  }
  .calendar-day-body p,
  .calendar-day-body strong,
  .calendar-day-footer {
    display: none;
  }
  .calendar-day-number {
    font-size: 1.12rem;
  }
  .calendar-day-label {
    font-size: 0.74rem;
  }
  .modal-fields {
    grid-template-columns: 1fr;
  }
}
@media (max-width: 520px) {
  .summary-grid {
    grid-template-columns: 1fr;
  }
  .nav { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  .nav a {
    padding: 0.7rem 0.4rem;
    font-size: 0.95rem;
  }
  .brand-block h1 {
    font-size: 1.95rem;
  }
  .lede {
    display: none;
  }
  .status-stack {
    grid-template-columns: 1fr;
  }
  .band-topline,
  .band-stats {
    flex-direction: column;
    align-items: start;
  }
  .chart-metrics {
    grid-template-columns: 1fr;
  }
  .calendar-modal {
    width: calc(100vw - 1rem);
    max-width: none;
    margin: auto;
  }
  .modal-card {
    min-height: calc(100vh - 1rem);
    border-radius: 24px;
    padding: 1rem;
    align-content: start;
  }
  .modal-actions {
    flex-direction: column-reverse;
  }
  .modal-actions button {
    width: 100%;
  }
}
"""


APP_JS = """
const appState = {
  livePlan: null,
  calendar: null,
  modalDay: null,
  scenarios: [],
  selectedScenarioId: "real",
};

const ROUTES = {
  "/": "overview",
  "/timeline": "timeline",
  "/tesla": "tesla",
};

const SCENARIO_STORAGE_KEY = "energySchedulerScenarioId";

const FLOW_SUPPLY_SERIES = [
  { key: "solar_kwh", label: "Solar", color: "#d08b3c" },
  { key: "import_kwh", label: "Grid import", color: "#4168ad" },
  { key: "battery_discharge_kwh", label: "Battery discharge", color: "#255d49" },
];

const FLOW_USE_SERIES = [
  { key: "fixed_load_kwh", label: "Base load", color: "#33483b" },
  { key: "flexible_load_kwh", label: "Flexible load", color: "#111111" },
  { key: "battery_charge_kwh", label: "Battery charge", color: "#b96a31" },
  { key: "export_kwh", label: "Grid export", color: "#a5481f" },
  { key: "curtail_kwh", label: "Curtailment", color: "#a8a18f" },
];

const BATTERY_LEGEND = [
  { label: "Battery SoC", color: "#255d49" },
  { label: "Reserve target", color: "#b96a31" },
  { label: "Emergency floor", color: "#a5481f" },
];

const TESLA_LEGEND = [
  { label: "Tesla charging", color: "#111111" },
];

function routeName() {
  return ROUTES[window.location.pathname] || "overview";
}

function selectedScenario() {
  return appState.scenarios.find((scenario) => scenario.id === appState.selectedScenarioId) || null;
}

function isReadOnlyScenario() {
  return Boolean(selectedScenario()?.read_only);
}

function scenarioApiPath(path) {
  const params = new URLSearchParams();
  params.set("scenario", appState.selectedScenarioId || "real");
  const query = params.toString();
  return `${path}${query ? `?${query}` : ""}`;
}

function normalizeScenarioId(requested) {
  if (!requested) return "real";
  return appState.scenarios.some((scenario) => scenario.id === requested) ? requested : "real";
}

function readScenarioIdFromLocation() {
  const params = new URLSearchParams(window.location.search);
  return params.get("scenario");
}

function persistScenarioSelection(replace = false) {
  try {
    window.localStorage.setItem(SCENARIO_STORAGE_KEY, appState.selectedScenarioId || "real");
  } catch (_error) {
    // Ignore localStorage failures in locked-down browsers.
  }
  const url = new URL(window.location.href);
  if (!appState.selectedScenarioId || appState.selectedScenarioId === "real") {
    url.searchParams.delete("scenario");
  } else {
    url.searchParams.set("scenario", appState.selectedScenarioId);
  }
  const next = `${url.pathname}${url.search}`;
  if (replace) {
    history.replaceState({}, "", next);
  } else {
    history.pushState({}, "", next);
  }
}

async function fetchJson(path, options = {}, attempt = 0) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(text || response.statusText);
  }
  if (!text.trim()) {
    if (attempt < 2) {
      await new Promise((resolve) => setTimeout(resolve, 120 * (attempt + 1)));
      return fetchJson(path, options, attempt + 1);
    }
    throw new Error(`Empty JSON response from ${path}`);
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    if (attempt < 2) {
      await new Promise((resolve) => setTimeout(resolve, 120 * (attempt + 1)));
      return fetchJson(path, options, attempt + 1);
    }
    throw error;
  }
}

function cleanNumber(value, epsilon = 1e-9) {
  return Math.abs(Number(value || 0)) < epsilon ? 0 : Number(value);
}

function fmt(value, suffix = "") {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") return `${cleanNumber(value).toFixed(2)}${suffix}`;
  return String(value);
}

function fmtShort(value, suffix = "") {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") return `${cleanNumber(value).toFixed(1)}${suffix}`;
  return String(value);
}

function fmtPrice(value) {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") return `${cleanNumber(value).toFixed(2)} CZK/kWh`;
  return String(value);
}

function fmtMoney(value) {
  if (value === null || value === undefined) return "—";
  if (typeof value === "number") return `${cleanNumber(value).toFixed(2)} CZK`;
  return String(value);
}

function sumKey(items, key) {
  return items.reduce((total, item) => total + Number(item[key] || 0), 0);
}

function averageKey(items, key) {
  if (!items.length) return 0;
  return sumKey(items, key) / items.length;
}

function maxBy(items, selector) {
  return items.reduce((best, item) => (best === null || selector(item) > selector(best) ? item : best), null);
}

function minBy(items, selector) {
  return items.reduce((best, item) => (best === null || selector(item) < selector(best) ? item : best), null);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatDateTime(value, options) {
  if (!value) return "—";
  const date = new Date(value);
  return new Intl.DateTimeFormat([], options).format(date);
}

function formatBucketTime(summary, bucketIndex, options = { hour: "2-digit", minute: "2-digit" }) {
  if (!summary.planner_timestamp) return `Bucket ${bucketIndex}`;
  const base = new Date(summary.planner_timestamp);
  const date = new Date(base.getTime() + bucketIndex * (summary.bucket_minutes || 15) * 60000);
  return new Intl.DateTimeFormat([], options).format(date);
}

function formatDayLabel(dateValue, options = { weekday: "short", day: "numeric", month: "short" }) {
  return formatDateTime(`${dateValue}T12:00:00`, options);
}

function aggregateTimeline(points, bucketMinutes, targetMinutes = 60, limitBuckets = 24) {
  const bucketsPerGroup = Math.max(1, Math.round(targetMinutes / bucketMinutes));
  const groups = [];
  for (let index = 0; index < points.length && groups.length < limitBuckets; index += bucketsPerGroup) {
    const chunk = points.slice(index, index + bucketsPerGroup);
    if (!chunk.length) continue;
    const group = {
      bucket_index: chunk[0].bucket_index,
      solar_kwh: sumKey(chunk, "solar_kwh"),
      import_kwh: sumKey(chunk, "import_kwh"),
      export_kwh: sumKey(chunk, "export_kwh"),
      fixed_load_kwh: sumKey(chunk, "fixed_load_kwh"),
      flexible_load_kwh: sumKey(chunk, "flexible_load_kwh"),
      battery_charge_kwh: sumKey(chunk, "battery_charge_kwh"),
      battery_discharge_kwh: sumKey(chunk, "battery_discharge_kwh"),
      curtail_kwh: sumKey(chunk, "curtail_kwh"),
      tesla_kwh: sumKey(chunk, "tesla_kwh"),
      battery_soc_kwh: Number(chunk[chunk.length - 1].battery_soc_kwh || 0),
      reserve_target_kwh: Number(chunk[chunk.length - 1].reserve_target_kwh || 0),
      emergency_floor_kwh: Number(chunk[chunk.length - 1].emergency_floor_kwh || 0),
      import_price_czk_per_kwh: averageKey(chunk, "import_price_czk_per_kwh"),
      export_price_czk_per_kwh: averageKey(chunk, "export_price_czk_per_kwh"),
    };
    group.supply_kwh = group.solar_kwh + group.import_kwh + group.battery_discharge_kwh;
    group.use_kwh = group.fixed_load_kwh + group.flexible_load_kwh + group.battery_charge_kwh + group.export_kwh + group.curtail_kwh;
    group.net_balance_kwh = group.supply_kwh - group.use_kwh;
    groups.push(group);
  }
  return groups;
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
  document.getElementById("planner-timestamp").textContent = summary.planner_timestamp
    ? formatDateTime(summary.planner_timestamp, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })
    : "—";
}

function renderScenarioPicker() {
  const select = document.getElementById("scenario-select");
  select.innerHTML = appState.scenarios.map((scenario) => `
    <option value="${escapeHtml(scenario.id)}">${escapeHtml(scenario.name)}</option>
  `).join("");
  select.value = appState.selectedScenarioId || "real";
}

function renderScenarioChrome() {
  const scenario = selectedScenario();
  const description = document.getElementById("scenario-description");
  const pill = document.getElementById("scenario-kind-pill");
  const status = document.getElementById("scenario-status");
  const banner = document.getElementById("source-banner");
  const readonlyNote = document.getElementById("calendar-readonly-note");

  if (!scenario) {
    description.textContent = "Scenario source is unavailable.";
    pill.textContent = "Unknown";
    status.textContent = "Unknown";
    banner.classList.add("hidden");
    readonlyNote.classList.add("hidden");
    return;
  }

  description.textContent = scenario.description || "";
  pill.textContent = scenario.kind === "real" ? "Live source" : "Seasonal demo";
  pill.className = `pill ${scenario.kind === "real" ? "" : "muted"}`;
  status.textContent = scenario.kind === "real" ? scenario.name : `${scenario.name} demo`;

  if (scenario.kind === "real") {
    banner.classList.add("hidden");
  } else {
    banner.classList.remove("hidden");
    banner.innerHTML = `<strong>${escapeHtml(scenario.name)} demo.</strong> This plan is synthetic seasonal data layered on top of your current Tesla planning hints. Calendar edits stay locked until you switch back to real-time mode.`;
  }

  if (isReadOnlyScenario()) {
    readonlyNote.classList.remove("hidden");
    readonlyNote.textContent = "Tesla day edits are disabled while you are previewing a fake seasonal scenario. Switch back to Real-time to change the live Tesla calendar.";
  } else {
    readonlyNote.classList.add("hidden");
    readonlyNote.textContent = "";
  }
}

function renderHeadline(summary) {
  const nextTesla = summary.next_tesla_day;
  const headline = document.getElementById("headline-card");
  let title = "The current plan is balanced";
  let body = "Nothing dominant is happening in the current bucket. The scheduler is mostly following its economic baseline.";
  if (summary.current_export_kwh > 0.05) {
    title = "The current plan is selling surplus energy";
    body = "Right now, export is beating the lowest-value flexible uses. That only makes sense if those uses are worth less than selling now and buying later if needed.";
  } else if (summary.current_tesla_kwh > 0.05) {
    title = "The current plan is charging the Tesla";
    body = "The planner currently values Tesla charging more than exporting or waiting. That usually means a departure target or future replacement cost is driving the decision.";
  } else if (summary.current_import_kwh > 0.05) {
    title = "The current plan is importing from the grid";
    body = "The model is choosing to buy now instead of draining the battery further. This usually happens when preserving battery value beats immediate discharge.";
  }
  headline.innerHTML = `
    <p class="eyebrow">What matters now</p>
    <h3>${escapeHtml(title)}</h3>
    <p>${escapeHtml(body)}</p>
    <div class="band-meta">
      <span class="pill">${fmtShort(summary.battery_soc_kwh, " kWh")} in battery</span>
      <span class="pill muted">${nextTesla ? `${formatDayLabel(nextTesla.date)} ${nextTesla.departure_time || ""}`.trim() : "No Tesla departure set"}</span>
      <span class="pill muted">${nextTesla ? `${Math.round((nextTesla.confidence || 0) * 100)}% Tesla confidence` : "Default-only Tesla planning"}</span>
    </div>
  `;
}

function renderSummary(summary) {
  const grid = document.getElementById("summary-grid");
  const items = [
    ["Battery now", fmtShort(summary.battery_soc_kwh, " kWh")],
    ["Reserve target", fmtShort(summary.battery_reserve_kwh, " kWh")],
    ["Import now", fmtShort(summary.current_import_kwh, " kWh")],
    ["Export now", fmtShort(summary.current_export_kwh, " kWh")],
    ["Flexible load now", fmtShort(summary.current_flexible_load_kwh, " kWh")],
    ["Tesla now", fmtShort(summary.current_tesla_kwh, " kWh")],
  ];
  grid.innerHTML = items.map(([label, value]) => `
    <div class="summary-card">
      <span>${label}</span>
      <strong>${value}</strong>
    </div>
  `).join("");
}

function renderMetricCards(targetId, items) {
  const target = document.getElementById(targetId);
  target.innerHTML = items.map((item) => `
    <article class="metric-card ${item.tone || ""}">
      <span class="metric-label">${escapeHtml(item.label)}</span>
      <strong class="metric-value">${escapeHtml(item.value)}</strong>
      <span class="metric-foot">${escapeHtml(item.foot || "")}</span>
    </article>
  `).join("");
}

function renderFlowMetrics(data, summary) {
  const totalSolar = sumKey(data, "solar_kwh");
  const totalImport = sumKey(data, "import_kwh");
  const totalExport = sumKey(data, "export_kwh");
  const totalFlexible = sumKey(data, "flexible_load_kwh");
  const totalTesla = sumKey(data, "tesla_kwh");
  const drift = sumKey(data, "net_balance_kwh");
  const peakImport = maxBy(data, (point) => Number(point.import_kwh || 0));
  renderMetricCards("flow-metrics", [
    {
      label: "Solar total",
      value: fmtShort(totalSolar, " kWh"),
      foot: "Expected generation over the next 24h.",
      tone: "ok",
    },
    {
      label: "Grid import",
      value: fmtShort(totalImport, " kWh"),
      foot: peakImport && peakImport.import_kwh > 0.01
        ? `Peak ${fmtShort(peakImport.import_kwh, " kWh")} around ${formatBucketTime(summary, peakImport.bucket_index)}.`
        : "No notable imports expected.",
    },
    {
      label: "Grid export",
      value: fmtShort(totalExport, " kWh"),
      foot: totalExport > 0.01 ? "Energy the model expects to sell." : "No export expected in the next 24h.",
    },
    {
      label: "Flexible demand",
      value: fmtShort(totalFlexible, " kWh"),
      foot: totalTesla > 0.01 ? `${fmtShort(totalTesla, " kWh")} of that is Tesla charging.` : "No Tesla charging is planned yet.",
    },
    {
      label: "Balance drift",
      value: fmtShort(drift, " kWh"),
      foot: Math.abs(drift) < 0.05 ? "This should stay near zero if the chart is honest." : "Non-zero means the chart aggregation is wrong.",
      tone: Math.abs(drift) < 0.05 ? "ok" : "warning",
    },
  ]);
}

function renderBatteryMetrics(data, summary) {
  const start = data[0];
  const end = data[data.length - 1];
  const peak = maxBy(data, (point) => Number(point.battery_soc_kwh || 0));
  const trough = minBy(data, (point) => Number(point.battery_soc_kwh || 0));
  const margin = minBy(data, (point) => Number(point.battery_soc_kwh || 0) - Number(point.emergency_floor_kwh || 0));
  renderMetricCards("battery-metrics", [
    {
      label: "Starts at",
      value: fmtShort(start?.battery_soc_kwh, " kWh"),
      foot: `Current battery state against a ${fmtShort(summary.battery_capacity_kwh, " kWh")} pack.`,
      tone: "ok",
    },
    {
      label: "Peaks at",
      value: fmtShort(peak?.battery_soc_kwh, " kWh"),
      foot: peak ? `Around ${formatBucketTime(summary, peak.bucket_index)}.` : "No peak yet.",
    },
    {
      label: "Ends at",
      value: fmtShort(end?.battery_soc_kwh, " kWh"),
      foot: "Expected battery state 24 hours from now.",
    },
    {
      label: "Lowest margin",
      value: fmtShort((margin?.battery_soc_kwh || 0) - (margin?.emergency_floor_kwh || 0), " kWh"),
      foot: trough ? `Lowest SoC is ${fmtShort(trough.battery_soc_kwh, " kWh")} around ${formatBucketTime(summary, trough.bucket_index)}.` : "No battery activity.",
      tone: (margin && ((margin.battery_soc_kwh || 0) - (margin.emergency_floor_kwh || 0) < 0.5)) ? "warning" : "",
    },
  ]);
}

function renderTeslaMetrics(data, summary) {
  const totalTesla = sumKey(data, "tesla_kwh");
  const firstCharge = data.find((point) => Number(point.tesla_kwh || 0) > 0.01);
  const lastCharge = [...data].reverse().find((point) => Number(point.tesla_kwh || 0) > 0.01);
  const nextTesla = summary.next_tesla_day;
  renderMetricCards("tesla-metrics", [
    {
      label: "Planned charge",
      value: fmtShort(totalTesla, " kWh"),
      foot: totalTesla > 0.01 ? "Energy the model wants to put into the car in the next 24h." : "No Tesla energy is scheduled in the next 24h.",
      tone: totalTesla > 0.01 ? "ok" : "",
    },
    {
      label: "First charge hour",
      value: firstCharge ? formatBucketTime(summary, firstCharge.bucket_index, { hour: "2-digit", minute: "2-digit" }) : "—",
      foot: firstCharge ? "When the next charging window starts." : "No charging window is active.",
    },
    {
      label: "Last charge hour",
      value: lastCharge ? formatBucketTime(summary, lastCharge.bucket_index, { hour: "2-digit", minute: "2-digit" }) : "—",
      foot: lastCharge ? "When the current charging plan tapers off." : "No charging window is active.",
    },
    {
      label: "Next departure",
      value: nextTesla ? `${formatDayLabel(nextTesla.date)} ${nextTesla.departure_time || ""}`.trim() : "Not set",
      foot: nextTesla ? `${Math.round((nextTesla.confidence || 0) * 100)}% confidence, target ${nextTesla.target_soc_pct || "—"}%.` : "Only default Tesla rules are active.",
    },
  ]);
}

function renderBandCards(bands) {
  const important = [...bands]
    .filter((band) => Number(band.target_quantity_kwh || 0) > 0.01)
    .sort((a, b) => {
      const requiredDelta = Number(b.required_level) - Number(a.required_level);
      if (requiredDelta !== 0) return requiredDelta;
      const probabilityDelta = Number(b.scenario_probability || 0) - Number(a.scenario_probability || 0);
      if (probabilityDelta !== 0) return probabilityDelta;
      return a.deadline_index - b.deadline_index;
    })
    .slice(0, 6);
  const container = document.getElementById("band-cards");
  if (!important.length) {
    container.innerHTML = `<div class="empty-state">No flexible demand bands are active inside the current horizon.</div>`;
    return;
  }
  container.innerHTML = important.map((band) => `
    <article class="band-card">
      <div class="band-topline">
        <div>
          <h3>${escapeHtml(band.display_name)}</h3>
          <p class="band-copy">${escapeHtml(describeBand(band))}</p>
        </div>
        <span class="pill ${band.required_level ? "" : "muted"}">${band.required_level ? "Required" : "Optional"}</span>
      </div>
      <div class="meter ${band.required_level && Number(band.shortfall_kwh || 0) > 0.01 ? "warning" : ""}">
        <span style="width:${Math.max(0, Math.min(100, progressPct(band)))}%"></span>
      </div>
      <div class="band-stats">
        <strong>${fmtShort(band.served_quantity_kwh, " kWh")} / ${fmtShort(band.target_quantity_kwh, " kWh")}</strong>
        <span>${bandStatusCopy(band)}</span>
      </div>
      <div class="band-meta">
        <span class="pill muted">${deadlineLabel(band)}</span>
        <span class="pill muted">${Math.round(Number(band.scenario_probability || band.confidence || 1) * 100)}% probability</span>
        <span class="pill ${bandStatusTone(band)}">${bandStatusLabel(band)}</span>
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

function deadlineLabel(band) {
  if (band.metadata && band.metadata.date && band.metadata.departure_time) {
    return `${formatDayLabel(band.metadata.date)} ${band.metadata.departure_time}`;
  }
  return formatBucketTime(appState.livePlan.summary || {}, Number(band.deadline_index || 0), {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function describeBand(band) {
  if (band.metadata && band.metadata.departure_time && band.metadata.target_soc_pct) {
    return `Tesla target of ${band.metadata.target_soc_pct}% by ${band.metadata.date} ${band.metadata.departure_time}.`;
  }
  return `${band.asset_id} should receive ${fmtShort(band.target_quantity_kwh, " kWh")} by ${deadlineLabel(band)}.`;
}

function progressPct(band) {
  const target = Number(band.target_quantity_kwh || 0);
  if (target <= 0) return 100;
  return (Number(band.served_quantity_kwh || 0) / target) * 100;
}

function bandStatusCopy(band) {
  const shortfall = Number(band.shortfall_kwh || 0);
  if (band.required_level) {
    return shortfall > 0.01 ? `${fmtShort(shortfall, " kWh")} shortfall risk` : "Covered in the modeled cases";
  }
  return shortfall > 0.01 ? `${fmtShort(shortfall, " kWh")} optional headroom left` : "Already worth taking in the current plan";
}

function bandStatusLabel(band) {
  const shortfall = Number(band.shortfall_kwh || 0);
  if (band.required_level) {
    return shortfall > 0.01 ? "Needs tuning" : "Covered";
  }
  return shortfall > 0.01 ? "Lower priority" : "Currently attractive";
}

function bandStatusTone(band) {
  const shortfall = Number(band.shortfall_kwh || 0);
  if (band.required_level) {
    return shortfall > 0.01 ? "warning" : "ok";
  }
  return shortfall > 0.01 ? "muted" : "ok";
}

function fmtDetailed(value, suffix = " kWh") {
  return `${cleanNumber(value).toFixed(2)}${suffix}`;
}

function formatHourRange(summary, bucketIndex, windowMinutes = 60) {
  if (!summary.planner_timestamp) return `Hour starting at bucket ${bucketIndex}`;
  const base = new Date(summary.planner_timestamp);
  const start = new Date(base.getTime() + bucketIndex * (summary.bucket_minutes || 15) * 60000);
  const end = new Date(start.getTime() + windowMinutes * 60000);
  const date = new Intl.DateTimeFormat([], { weekday: "short", month: "short", day: "numeric" }).format(start);
  const time = new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit" });
  return `${date}, ${time.format(start)}-${time.format(end)}`;
}

function renderChartTooltip(title, rows, footer = "") {
  return `
    <h4>${escapeHtml(title)}</h4>
    <div class="chart-tooltip-list">
      ${rows.map((row) => `
        <div class="chart-tooltip-row">
          <span class="chart-tooltip-key">
            <span class="chart-tooltip-swatch" style="background:${row.color}"></span>
            ${escapeHtml(row.label)}
          </span>
          <span class="chart-tooltip-value">${escapeHtml(row.value)}</span>
        </div>
      `).join("")}
    </div>
    ${footer ? `<div class="chart-tooltip-foot">${escapeHtml(footer)}</div>` : ""}
  `;
}

function attachChartHover(target, options) {
  const svg = target.querySelector("svg");
  if (!svg || !options.data.length) return;

  let tooltip = target.querySelector(".chart-tooltip");
  if (!tooltip) {
    tooltip = document.createElement("div");
    tooltip.className = "chart-tooltip";
    target.appendChild(tooltip);
  }

  const hoverBand = svg.querySelector("[data-hover-band]");
  const hoverLine = svg.querySelector("[data-hover-line]");
  const hoverDot = svg.querySelector("[data-hover-dot]");

  function indexAt(clientX) {
    const rect = svg.getBoundingClientRect();
    const localX = clientX - rect.left;
    let bestIndex = 0;
    let bestDistance = Number.POSITIVE_INFINITY;
    options.centers.forEach((center, index) => {
      const px = center * (rect.width / options.viewWidth);
      const distance = Math.abs(px - localX);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = index;
      }
    });
    return bestIndex;
  }

  function hide() {
    tooltip.classList.remove("visible");
    if (hoverBand) hoverBand.style.opacity = "0";
    if (hoverLine) hoverLine.style.opacity = "0";
    if (hoverDot) hoverDot.style.opacity = "0";
  }

  function show(index, clientX, clientY) {
    const point = options.data[index];
    const frameRect = target.getBoundingClientRect();
    const svgRect = svg.getBoundingClientRect();
    const scaleX = svgRect.width / options.viewWidth;
    const scaleY = svgRect.height / options.viewHeight;
    const centerX = options.centers[index];

    tooltip.innerHTML = options.tooltip(point, index);
    tooltip.classList.add("visible");

    if (hoverBand) {
      hoverBand.setAttribute("x", String(centerX - options.hoverBandWidth / 2));
      hoverBand.style.opacity = "1";
    }
    if (hoverLine) {
      hoverLine.setAttribute("x1", String(centerX));
      hoverLine.setAttribute("x2", String(centerX));
      hoverLine.style.opacity = "1";
    }
    if (hoverDot && typeof options.hoverDotY === "function") {
      hoverDot.setAttribute("cx", String(centerX));
      hoverDot.setAttribute("cy", String(options.hoverDotY(point, index)));
      hoverDot.style.opacity = "1";
    }

    requestAnimationFrame(() => {
      const tooltipRect = tooltip.getBoundingClientRect();
      let left = centerX * scaleX;
      left = Math.max((tooltipRect.width / 2) + 12, Math.min(frameRect.width - (tooltipRect.width / 2) - 12, left));

      const cursorY = clientY - frameRect.top;
      const showAbove = cursorY > (tooltipRect.height + 28);
      tooltip.style.left = `${left}px`;
      tooltip.style.top = `${showAbove ? cursorY : cursorY + 18}px`;
      tooltip.style.transform = showAbove ? "translate(-50%, -100%)" : "translate(-50%, 0%)";
    });
  }

  function handlePointer(event) {
    const bounds = svg.getBoundingClientRect();
    if (
      event.clientX < bounds.left ||
      event.clientX > bounds.right ||
      event.clientY < bounds.top ||
      event.clientY > bounds.bottom
    ) {
      hide();
      return;
    }
    const index = indexAt(event.clientX);
    show(index, event.clientX, event.clientY);
  }

  svg.addEventListener("mousemove", handlePointer);
  svg.addEventListener("mouseleave", hide);
  svg.addEventListener("click", handlePointer);
  svg.addEventListener("touchstart", (event) => {
    const touch = event.touches[0];
    if (!touch) return;
    handlePointer(touch);
  }, { passive: true });
  target.addEventListener("mouseleave", hide);
}

function renderEmptyChart(targetId, message) {
  const target = document.getElementById(targetId);
  target.innerHTML = `
    <svg viewBox="0 0 1100 320" role="img" aria-label="${escapeHtml(message)}">
      <text x="550" y="165" text-anchor="middle" class="chart-empty">${escapeHtml(message)}</text>
    </svg>
  `;
}

function renderFlowChart(points, summary) {
  const target = document.getElementById("flow-chart");
  const data = aggregateTimeline(points, summary.bucket_minutes || 15, 60, 24);
  if (!data.length) {
    renderEmptyChart("flow-chart", "No timeline data yet.");
    return;
  }

  const width = 1100;
  const height = 400;
  const left = 72;
  const right = 24;
  const top = 26;
  const bottom = 62;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const zeroY = top + plotHeight / 2;
  const step = plotWidth / data.length;
  const barWidth = Math.max(14, step * 0.66);
  const maxAbs = Math.max(
    0.5,
    ...data.map((point) => Math.max(point.supply_kwh || 0, point.use_kwh || 0)),
  );
  const scale = ((plotHeight / 2) - 18) / maxAbs;

  const xFor = (index) => left + index * step + (step - barWidth) / 2;
  const yTopFor = (value) => zeroY - value * scale;
  const yBottomFor = (value) => zeroY + value * scale;
  const centers = data.map((_, index) => xFor(index) + barWidth / 2);

  const gridLevels = [maxAbs, maxAbs / 2, 0, -maxAbs / 2, -maxAbs];
  const grid = gridLevels.map((level) => {
    const y = level >= 0 ? yTopFor(level) : yBottomFor(Math.abs(level));
    return `
      <line x1="${left}" y1="${y}" x2="${left + plotWidth}" y2="${y}" class="chart-grid" />
      <text x="${left - 10}" y="${y + 4}" text-anchor="end" class="axis-label">${level.toFixed(1)}</text>
    `;
  }).join("");

  const bars = data.map((point, index) => {
    let positiveCursor = zeroY;
    let negativeCursor = zeroY;
    const supplyRects = FLOW_SUPPLY_SERIES.map((series) => {
      const value = Number(point[series.key] || 0);
      if (value <= 0) return "";
      const heightValue = value * scale;
      const y = positiveCursor - heightValue;
      positiveCursor = y;
      return `<rect x="${xFor(index)}" y="${y}" width="${barWidth}" height="${heightValue}" rx="6" fill="${series.color}" />`;
    }).join("");
    const useRects = FLOW_USE_SERIES.map((series) => {
      const value = Number(point[series.key] || 0);
      if (value <= 0) return "";
      const heightValue = value * scale;
      const y = negativeCursor;
      negativeCursor += heightValue;
      return `<rect x="${xFor(index)}" y="${y}" width="${barWidth}" height="${heightValue}" rx="6" fill="${series.color}" />`;
    }).join("");
    return `${supplyRects}${useRects}`;
  }).join("");

  const tickEvery = data.length > 16 ? 4 : 2;
  const ticks = data.map((point, index) => {
    if (index % tickEvery !== 0 && index !== data.length - 1) return "";
    const x = xFor(index) + barWidth / 2;
    return `
      <text x="${x}" y="${height - 20}" text-anchor="middle" class="axis-label">
        ${escapeHtml(formatBucketTime(summary, point.bucket_index))}
      </text>
    `;
  }).join("");

  target.innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Hourly energy balance">
      ${grid}
      <rect data-hover-band class="chart-hover-band" x="${left}" y="${top}" width="${Math.max(step * 0.92, barWidth + 8)}" height="${plotHeight}" rx="12"></rect>
      <line x1="${left}" y1="${zeroY}" x2="${left + plotWidth}" y2="${zeroY}" class="chart-axis" />
      ${bars}
      ${ticks}
    </svg>
  `;
  attachChartHover(target, {
    data,
    centers,
    viewWidth: width,
    viewHeight: height,
    hoverBandWidth: Math.max(step * 0.92, barWidth + 8),
    tooltip: (point) => {
      const importCost = Number(point.import_kwh || 0) * Number(point.import_price_czk_per_kwh || 0);
      const exportRevenue = Number(point.export_kwh || 0) * Number(point.export_price_czk_per_kwh || 0);
      return renderChartTooltip(
        formatHourRange(summary, point.bucket_index),
        [
          { label: "Solar", value: fmtDetailed(point.solar_kwh), color: "#d08b3c" },
          { label: "Grid import", value: fmtDetailed(point.import_kwh), color: "#4168ad" },
          { label: "Battery discharge", value: fmtDetailed(point.battery_discharge_kwh), color: "#255d49" },
          { label: "Base load", value: fmtDetailed(point.fixed_load_kwh), color: "#33483b" },
          { label: "Flexible load", value: fmtDetailed(point.flexible_load_kwh), color: "#111111" },
          { label: "Battery charge", value: fmtDetailed(point.battery_charge_kwh), color: "#b96a31" },
          { label: "Grid export", value: fmtDetailed(point.export_kwh), color: "#a5481f" },
          { label: "Curtailment", value: fmtDetailed(point.curtail_kwh), color: "#a8a18f" },
          { label: "Import price", value: fmtPrice(point.import_price_czk_per_kwh), color: "#d8d1c2" },
          { label: "Export price", value: fmtPrice(point.export_price_czk_per_kwh), color: "#d8d1c2" },
        ],
        `Supply ${fmtDetailed(point.supply_kwh)} vs use ${fmtDetailed(point.use_kwh)}. Drift ${fmtDetailed(point.net_balance_kwh)}. Market delta ${fmtMoney(exportRevenue - importCost)} for this hour.`
      );
    },
  });
}

function buildLinePath(points, xFor, yFor) {
  return points.map((point, index) => `${index === 0 ? "M" : "L"} ${xFor(index)} ${yFor(point)}`).join(" ");
}

function renderBatteryChart(points, summary) {
  const target = document.getElementById("battery-chart");
  const data = aggregateTimeline(points, summary.bucket_minutes || 15, 60, 24);
  if (!data.length) {
    renderEmptyChart("battery-chart", "No battery timeline data yet.");
    return;
  }

  const width = 1100;
  const height = 360;
  const left = 72;
  const right = 24;
  const top = 24;
  const bottom = 56;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const maxY = Math.max(
    Number(summary.battery_capacity_kwh || 0),
    ...data.map((point) => Math.max(point.battery_soc_kwh || 0, point.reserve_target_kwh || 0, point.emergency_floor_kwh || 0)),
    1,
  );
  const step = plotWidth / Math.max(1, data.length - 1);
  const xFor = (index) => left + step * index;
  const yFor = (value) => top + plotHeight - (Math.max(0, value) / maxY) * plotHeight;
  const centers = data.map((_, index) => xFor(index));

  const areaPath = [
    `M ${xFor(0)} ${top + plotHeight}`,
    ...data.map((point, index) => `L ${xFor(index)} ${yFor(point.battery_soc_kwh || 0)}`),
    `L ${xFor(data.length - 1)} ${top + plotHeight}`,
    "Z",
  ].join(" ");
  const socPath = buildLinePath(data, xFor, (point) => yFor(point.battery_soc_kwh || 0));
  const reservePath = buildLinePath(data, xFor, (point) => yFor(point.reserve_target_kwh || 0));
  const emergencyPath = buildLinePath(data, xFor, (point) => yFor(point.emergency_floor_kwh || 0));

  const gridValues = [maxY, maxY / 2, 0];
  const grid = gridValues.map((value) => `
    <line x1="${left}" y1="${yFor(value)}" x2="${left + plotWidth}" y2="${yFor(value)}" class="chart-grid" />
    <text x="${left - 10}" y="${yFor(value) + 4}" text-anchor="end" class="axis-label">${value.toFixed(1)}</text>
  `).join("");

  const tickEvery = data.length > 16 ? 4 : 2;
  const ticks = data.map((point, index) => {
    if (index % tickEvery !== 0 && index !== data.length - 1) return "";
    return `<text x="${xFor(index)}" y="${height - 18}" text-anchor="middle" class="axis-label">${escapeHtml(formatBucketTime(summary, point.bucket_index))}</text>`;
  }).join("");

  target.innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Battery state of charge">
      ${grid}
      <line data-hover-line class="chart-hover-line" x1="${left}" y1="${top}" x2="${left}" y2="${top + plotHeight}"></line>
      <path d="${areaPath}" class="chart-area" />
      <path d="${socPath}" class="chart-line-primary" />
      <path d="${reservePath}" class="chart-line-secondary" />
      <path d="${emergencyPath}" class="chart-line-danger" />
      <circle data-hover-dot class="chart-hover-dot" cx="${left}" cy="${top + plotHeight}" r="6"></circle>
      ${ticks}
    </svg>
  `;
  attachChartHover(target, {
    data,
    centers,
    viewWidth: width,
    viewHeight: height,
    hoverBandWidth: step,
    hoverDotY: (point) => yFor(point.battery_soc_kwh || 0),
    tooltip: (point) => {
      const reserveMargin = Number(point.battery_soc_kwh || 0) - Number(point.reserve_target_kwh || 0);
      const emergencyMargin = Number(point.battery_soc_kwh || 0) - Number(point.emergency_floor_kwh || 0);
      return renderChartTooltip(
        formatHourRange(summary, point.bucket_index),
        [
          { label: "Battery SoC", value: fmtDetailed(point.battery_soc_kwh), color: "#255d49" },
          { label: "Reserve target", value: fmtDetailed(point.reserve_target_kwh), color: "#b96a31" },
          { label: "Emergency floor", value: fmtDetailed(point.emergency_floor_kwh), color: "#a5481f" },
          { label: "Battery charge", value: fmtDetailed(point.battery_charge_kwh), color: "#b96a31" },
          { label: "Battery discharge", value: fmtDetailed(point.battery_discharge_kwh), color: "#4168ad" },
          { label: "Import price", value: fmtPrice(point.import_price_czk_per_kwh), color: "#d8d1c2" },
          { label: "Export price", value: fmtPrice(point.export_price_czk_per_kwh), color: "#d8d1c2" },
        ],
        `${fmtDetailed(point.battery_soc_kwh)} stored at the end of this hour. Reserve margin ${fmtDetailed(reserveMargin)}. Emergency margin ${fmtDetailed(emergencyMargin)}.`
      );
    },
  });
}

function renderTeslaChart(points, summary) {
  const target = document.getElementById("tesla-chart");
  const data = aggregateTimeline(points, summary.bucket_minutes || 15, 60, 24);
  if (!data.length || data.every((point) => Number(point.tesla_kwh || 0) < 0.01)) {
    renderEmptyChart("tesla-chart", "No Tesla charging is planned in the next 24 hours.");
    return;
  }

  const width = 1100;
  const height = 320;
  const left = 72;
  const right = 24;
  const top = 24;
  const bottom = 56;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const maxY = Math.max(0.5, ...data.map((point) => Number(point.tesla_kwh || 0)));
  const step = plotWidth / data.length;
  const barWidth = Math.max(14, step * 0.66);
  const yFor = (value) => top + plotHeight - (value / maxY) * plotHeight;
  const centers = data.map((_, index) => left + index * step + barWidth / 2);

  const gridValues = [maxY, maxY / 2, 0];
  const grid = gridValues.map((value) => `
    <line x1="${left}" y1="${yFor(value)}" x2="${left + plotWidth}" y2="${yFor(value)}" class="chart-grid" />
    <text x="${left - 10}" y="${yFor(value) + 4}" text-anchor="end" class="axis-label">${value.toFixed(1)}</text>
  `).join("");

  const bars = data.map((point, index) => {
    const value = Number(point.tesla_kwh || 0);
    const barHeight = (value / maxY) * plotHeight;
    return `<rect x="${left + index * step + (step - barWidth) / 2}" y="${top + plotHeight - barHeight}" width="${barWidth}" height="${barHeight}" rx="6" fill="#111111" />`;
  }).join("");

  const tickEvery = data.length > 16 ? 4 : 2;
  const ticks = data.map((point, index) => {
    if (index % tickEvery !== 0 && index !== data.length - 1) return "";
    return `<text x="${left + index * step + barWidth / 2}" y="${height - 18}" text-anchor="middle" class="axis-label">${escapeHtml(formatBucketTime(summary, point.bucket_index))}</text>`;
  }).join("");

  target.innerHTML = `
    <svg viewBox="0 0 ${width} ${height}" role="img" aria-label="Planned Tesla charging">
      ${grid}
      <rect data-hover-band class="chart-hover-band" x="${left}" y="${top}" width="${Math.max(step * 0.92, barWidth + 8)}" height="${plotHeight}" rx="12"></rect>
      ${bars}
      ${ticks}
    </svg>
  `;
  attachChartHover(target, {
    data,
    centers,
    viewWidth: width,
    viewHeight: height,
    hoverBandWidth: Math.max(step * 0.92, barWidth + 8),
    tooltip: (point) => {
      const flexibleLoad = Number(point.flexible_load_kwh || 0);
      const teslaLoad = Number(point.tesla_kwh || 0);
      const teslaShare = flexibleLoad > 0 ? (teslaLoad / flexibleLoad) * 100 : 0;
      return renderChartTooltip(
        formatHourRange(summary, point.bucket_index),
        [
          { label: "Tesla charging", value: fmtDetailed(point.tesla_kwh), color: "#111111" },
          { label: "Flexible load total", value: fmtDetailed(point.flexible_load_kwh), color: "#111111" },
          { label: "Solar", value: fmtDetailed(point.solar_kwh), color: "#d08b3c" },
          { label: "Grid import", value: fmtDetailed(point.import_kwh), color: "#4168ad" },
          { label: "Battery discharge", value: fmtDetailed(point.battery_discharge_kwh), color: "#255d49" },
          { label: "Import price", value: fmtPrice(point.import_price_czk_per_kwh), color: "#d8d1c2" },
          { label: "Export price", value: fmtPrice(point.export_price_czk_per_kwh), color: "#d8d1c2" },
        ],
        `Tesla is ${teslaShare.toFixed(0)}% of flexible demand in this hour. Importing this hour costs about ${fmtMoney(Number(point.tesla_kwh || 0) * Number(point.import_price_czk_per_kwh || 0))} if it all comes from the grid.`
      );
    },
  });
}

function renderTeslaSummary(days) {
  const nextExplicit = days.find((day) => day.mode === "explicit_departure");
  const nextFallback = days.find((day) => day.mode === "no_departure");
  document.getElementById("tesla-summary").innerHTML = `
    <p><strong>Default days</strong> use the recurring weekday pattern with low confidence. They are meant as a hint, not a promise.</p>
    <p><strong>Explicit departure days</strong> override the default schedule and are taken at 90% confidence.</p>
    <p><strong>No departure days</strong> still keep a 10% fallback default scenario, so the planner stays a little conservative.</p>
    <div class="band-meta">
      <span class="pill">${nextExplicit ? `Next explicit: ${formatDayLabel(nextExplicit.date)}` : "No explicit departures yet"}</span>
      <span class="pill muted">${nextFallback ? `No-departure fallback set on ${formatDayLabel(nextFallback.date)}` : "No no-departure overrides"}</span>
    </div>
  `;
}

function dayStatusLabel(day) {
  if (day.mode === "explicit_departure") {
    return day.departure_time ? `Departure ${day.departure_time}` : "Departure set";
  }
  if (day.mode === "no_departure") {
    return "No departure";
  }
  if (day.departure_time && day.target_soc_pct !== null) {
    return `Default ${day.departure_time}`;
  }
  return "No schedule";
}

function dayStatusCopy(day) {
  if (day.mode === "explicit_departure" && day.departure_time) {
    return `Target ${day.target_soc_pct}% at ${day.departure_time}`;
  }
  if (day.mode === "no_departure") {
    return day.departure_time ? `Fallback ${day.departure_time} at ${Math.round((day.confidence || 0) * 100)}%` : "Planner assumes the car stays home.";
  }
  if (day.departure_time) {
    return `Default ${day.target_soc_pct}% with ${Math.round((day.confidence || 0) * 100)}% confidence`;
  }
  return "No recurring departure is configured for this day.";
}

function modalElements() {
  return {
    dialog: document.getElementById("calendar-modal"),
    form: document.getElementById("calendar-modal-form"),
    title: document.getElementById("calendar-modal-title"),
    copy: document.getElementById("calendar-modal-copy"),
    time: document.getElementById("calendar-modal-time"),
    soc: document.getElementById("calendar-modal-soc"),
    cancel: document.getElementById("calendar-modal-cancel"),
    close: document.getElementById("calendar-modal-close"),
  };
}

function selectedModalMode() {
  const checked = document.querySelector('input[name="mode"]:checked');
  return checked ? checked.value : "default";
}

function syncCalendarModal() {
  const { time, soc } = modalElements();
  const mode = selectedModalMode();
  const isExplicit = mode === "explicit_departure";
  time.disabled = !isExplicit;
  soc.disabled = !isExplicit;
  if (!isExplicit) {
    time.value = "";
    soc.value = "";
  }
}

function openCalendarModal(day) {
  if (isReadOnlyScenario()) {
    return;
  }
  appState.modalDay = day;
  const { dialog, title, copy, time, soc } = modalElements();
  title.textContent = formatDateTime(`${day.date}T12:00:00`, { weekday: "long", day: "numeric", month: "long" });
  copy.textContent = `Choose what kind of Tesla day this is. Explicit departures are treated as 90% confidence. "No departure" still keeps a 10% fallback if your recurring schedule says the car usually leaves that day.`;
  document.querySelectorAll('input[name="mode"]').forEach((input) => {
    input.checked = input.value === day.mode;
  });
  time.value = day.mode === "explicit_departure" ? (day.departure_time || "") : "";
  soc.value = day.mode === "explicit_departure" ? (day.target_soc_pct ?? "") : "";
  syncCalendarModal();
  dialog.showModal();
}

function closeCalendarModal() {
  const { dialog, form } = modalElements();
  form.reset();
  dialog.close();
  appState.modalDay = null;
}

async function saveModalDay(event) {
  event.preventDefault();
  if (!appState.modalDay) return;
  if (isReadOnlyScenario()) {
    closeCalendarModal();
    return;
  }
  const { time, soc } = modalElements();
  const payload = {
    mode: selectedModalMode(),
    departure_time: time.value || null,
    target_soc_pct: soc.value || null,
  };
  await fetchJson(`/api/tesla/calendar/${appState.modalDay.date}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });
  closeCalendarModal();
  await boot();
}

function renderCalendar(days) {
  const container = document.getElementById("calendar-grid");
  container.innerHTML = "";
  if (!days.length) {
    renderTeslaSummary(days);
    return;
  }
  const firstWeekday = (new Date(`${days[0].date}T12:00:00`).getDay() + 6) % 7;
  for (let index = 0; index < firstWeekday; index += 1) {
    const blank = document.createElement("div");
    blank.className = "calendar-blank";
    container.appendChild(blank);
  }
  days.forEach((day) => {
    const button = document.createElement("button");
    const isToday = day.date === new Date().toISOString().slice(0, 10);
    button.className = `calendar-day ${day.mode === "explicit_departure" ? "explicit" : ""} ${day.mode === "no_departure" ? "no-departure" : ""} ${isToday ? "today" : ""}`.trim();
    button.type = "button";
    button.disabled = isReadOnlyScenario();
    button.innerHTML = `
      <div class="calendar-day-header">
        <div>
          <div class="calendar-day-number">${escapeHtml(formatDateTime(`${day.date}T12:00:00`, { day: "numeric" }))}</div>
          <div class="calendar-day-label">${escapeHtml(formatDateTime(`${day.date}T12:00:00`, { month: "short" }))}</div>
        </div>
        <span class="pill ${day.mode === "explicit_departure" ? "" : "muted"}">${Math.round((day.confidence || 0) * 100)}%</span>
      </div>
      <div class="calendar-day-body">
        <strong>${escapeHtml(dayStatusLabel(day))}</strong>
        <p>${escapeHtml(dayStatusCopy(day))}</p>
      </div>
      <div class="calendar-day-footer">
        <span class="pill muted">${day.mode === "explicit_departure" ? "Departure set" : day.mode === "no_departure" ? "Staying home" : "Default rule"}</span>
      </div>
    `;
    if (!button.disabled) {
      button.addEventListener("click", () => openCalendarModal(day));
    }
    container.appendChild(button);
  });
  renderTeslaSummary(days);
}

function renderLivePlan() {
  const livePlan = appState.livePlan;
  const summary = livePlan.summary || {};
  const timeline = livePlan.telemetry_timeline || [];
  const hourly = aggregateTimeline(timeline, summary.bucket_minutes || 15, 60, 24);
  renderScenarioChrome();
  renderStatus(summary);
  renderHeadline(summary);
  renderSummary(summary);
  renderBandCards(livePlan.bands || []);
  renderLegend("flow-legend", [...FLOW_SUPPLY_SERIES, ...FLOW_USE_SERIES]);
  renderLegend("battery-legend", BATTERY_LEGEND);
  renderLegend("tesla-legend", TESLA_LEGEND);
  renderFlowMetrics(hourly, summary);
  renderBatteryMetrics(hourly, summary);
  renderTeslaMetrics(hourly, summary);
  renderFlowChart(timeline, summary);
  renderBatteryChart(timeline, summary);
  renderTeslaChart(timeline, summary);
}

async function refreshPlanAndCalendar() {
  const [livePlan, calendar] = await Promise.all([
    fetchJson(scenarioApiPath("/api/live/plan")),
    fetchJson("/api/tesla/calendar"),
  ]);
  appState.livePlan = livePlan;
  appState.calendar = calendar;
  renderLivePlan();
  renderCalendar(appState.calendar.days || []);
}

async function boot() {
  const scenarioPayload = await fetchJson("/api/scenarios");
  appState.scenarios = scenarioPayload.scenarios || [];
  let requestedScenario = readScenarioIdFromLocation();
  if (!requestedScenario) {
    try {
      requestedScenario = window.localStorage.getItem(SCENARIO_STORAGE_KEY);
    } catch (_error) {
      requestedScenario = null;
    }
  }
  appState.selectedScenarioId = normalizeScenarioId(requestedScenario);
  renderScenarioPicker();
  persistScenarioSelection(true);
  renderNav();
  renderScenarioChrome();
  await refreshPlanAndCalendar();
}

function handleNavigation(event) {
  const link = event.target.closest("[data-route]");
  if (!link) return;
  event.preventDefault();
  const url = new URL(link.getAttribute("href"), window.location.origin);
  if (window.location.search) {
    url.search = window.location.search;
  }
  history.pushState({}, "", `${url.pathname}${url.search}`);
  renderNav();
}

document.addEventListener("click", handleNavigation);
window.addEventListener("popstate", async () => {
  appState.selectedScenarioId = normalizeScenarioId(readScenarioIdFromLocation() || "real");
  renderScenarioPicker();
  renderNav();
  renderScenarioChrome();
  await refreshPlanAndCalendar();
});
document.addEventListener("change", (event) => {
  if (event.target.matches('input[name="mode"]')) {
    syncCalendarModal();
  }
});
document.getElementById("scenario-select").addEventListener("change", async (event) => {
  appState.selectedScenarioId = normalizeScenarioId(event.target.value);
  persistScenarioSelection();
  renderScenarioPicker();
  renderScenarioChrome();
  await refreshPlanAndCalendar();
});
document.getElementById("calendar-modal-form").addEventListener("submit", saveModalDay);
document.getElementById("calendar-modal-cancel").addEventListener("click", closeCalendarModal);
document.getElementById("calendar-modal-close").addEventListener("click", closeCalendarModal);

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

    def scenarios(self) -> dict[str, object]:
        return {"scenarios": scenario_catalog()}

    def plan_for_scenario(self, scenario_id: str) -> dict[str, object]:
        metadata = scenario_metadata(scenario_id)
        if scenario_id == "real":
            plan = dict(self.latest_plan())
        else:
            plan = self.scheduler.simulate(build_scenario_overrides(self.config, scenario_id, datetime.now().astimezone()))
        summary = dict(plan.get("summary", {}))
        summary["scenario_id"] = metadata["id"]
        summary["scenario_name"] = metadata["name"]
        summary["scenario_kind"] = metadata["kind"]
        summary["scenario_read_only"] = bool(metadata.get("read_only", False))
        plan["summary"] = summary
        plan["selected_scenario"] = metadata
        return plan

    def get_calendar(self) -> dict[str, object]:
        tesla = self.config.assets.get("tesla", {})
        return load_or_create_calendar(self.state_dir, tesla.get("recurring_schedule", []), persist=True)

    def update_calendar(self, day_date: str, payload: dict[str, object]) -> dict[str, object]:
        tesla = self.config.assets.get("tesla", {})
        return update_calendar_day(self.state_dir, tesla.get("recurring_schedule", []), day_date, payload)


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
        parsed = urlparse(self.path)
        path = parsed.path
        params = parse_qs(parsed.query)
        scenario_id = params.get("scenario", ["real"])[0]
        try:
            if path in {"/", "/timeline", "/tesla"}:
                self._text(INDEX_HTML, "text/html; charset=utf-8")
            elif path == "/favicon.ico":
                self.send_response(HTTPStatus.NO_CONTENT)
                self.end_headers()
            elif path == "/styles.css":
                self._text(APP_CSS, "text/css; charset=utf-8")
            elif path == "/app.js":
                self._text(APP_JS, "application/javascript; charset=utf-8")
            elif path == "/api/scenarios":
                self._json(self.ui.scenarios())
            elif path == "/api/live/summary":
                latest = self.ui.plan_for_scenario(scenario_id)
                self._json({"summary": latest["summary"]})
            elif path == "/api/live/plan":
                self._json(self.ui.plan_for_scenario(scenario_id))
            elif path == "/api/live/bands":
                self._json({"bands": self.ui.plan_for_scenario(scenario_id).get("bands", [])})
            elif path == "/api/live/telemetry":
                self._json({"telemetry_timeline": self.ui.plan_for_scenario(scenario_id).get("telemetry_timeline", [])})
            elif path == "/api/tesla/calendar":
                self._json(self.ui.get_calendar())
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
