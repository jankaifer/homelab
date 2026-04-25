import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import type { DashboardResponse, DemandBand, HistoryEntry, PlannerSnapshot, PlannerSummary, TelemetryPoint } from "./shared";

const styles = `
:root {
  color-scheme: light;
  --bg: #fafafa;
  --panel: #ffffff;
  --ink: #09090b;
  --muted: #71717a;
  --soft: #f4f4f5;
  --line: #e4e4e7;
  --strong-line: #d4d4d8;
  --accent: #000000;
  --good: #047857;
  --warn: #b45309;
  --bad: #b91c1c;
  --blue: #2563eb;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
button, input { font: inherit; }
button {
  border: 1px solid var(--line);
  border-radius: 6px;
  background: var(--panel);
  color: var(--ink);
  padding: 0.55rem 0.8rem;
  font-weight: 500;
  cursor: pointer;
}
button.primary { background: var(--ink); color: white; border-color: var(--ink); }
button:hover { border-color: var(--strong-line); }
input {
  border: 1px solid var(--line);
  border-radius: 6px;
  padding: 0.55rem 0.7rem;
  background: var(--panel);
  color: var(--ink);
}
.shell {
  width: min(1360px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 24px 0 48px;
}
.topbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  padding-bottom: 20px;
  border-bottom: 1px solid var(--line);
}
.brand { display: grid; gap: 4px; }
.brand h1 { margin: 0; font-size: 1.08rem; letter-spacing: 0; }
.brand span, .muted { color: var(--muted); }
.date-controls {
  display: flex;
  gap: 8px;
  align-items: center;
  flex-wrap: wrap;
}
.grid { display: grid; gap: 16px; }
.metrics {
  grid-template-columns: repeat(6, minmax(0, 1fr));
  margin: 20px 0 16px;
}
.two-up { grid-template-columns: minmax(0, 1.45fr) minmax(360px, 0.75fr); }
.panel {
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--panel);
}
.panel-pad { padding: 16px; }
.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: start;
  gap: 16px;
  padding: 14px 16px;
  border-bottom: 1px solid var(--line);
}
.panel-header h2, .panel-header h3 { margin: 0; font-size: 0.96rem; letter-spacing: 0; }
.panel-header p, .metric span, .table small { margin: 4px 0 0; color: var(--muted); font-size: 0.82rem; }
.metric {
  padding: 14px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--panel);
  min-width: 0;
}
.metric strong {
  display: block;
  margin-top: 6px;
  font-size: 1.18rem;
  line-height: 1.2;
  overflow-wrap: anywhere;
}
.chart-wrap { padding: 14px 16px 16px; }
.chart {
  width: 100%;
  height: 320px;
  display: block;
}
.axis { stroke: var(--line); stroke-width: 1; }
.tick { fill: var(--muted); font-size: 11px; }
.legend {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  color: var(--muted);
  font-size: 0.82rem;
}
.legend span { display: inline-flex; align-items: center; gap: 6px; }
.dot { width: 8px; height: 8px; border-radius: 99px; display: inline-block; }
.stack { display: grid; gap: 10px; }
.band {
  display: grid;
  gap: 8px;
  padding: 12px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--panel);
}
.band-head { display: flex; justify-content: space-between; gap: 12px; }
.band strong { font-size: 0.92rem; }
.pill {
  display: inline-flex;
  align-items: center;
  width: fit-content;
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 2px 8px;
  color: var(--muted);
  font-size: 0.75rem;
  white-space: nowrap;
}
.bar {
  height: 7px;
  background: var(--soft);
  border-radius: 99px;
  overflow: hidden;
}
.bar > i { display: block; height: 100%; background: var(--ink); border-radius: inherit; }
.table {
  width: 100%;
  border-collapse: collapse;
}
.table th, .table td {
  padding: 10px 12px;
  border-bottom: 1px solid var(--line);
  text-align: left;
  font-size: 0.86rem;
}
.table th {
  color: var(--muted);
  font-weight: 500;
  background: #fcfcfc;
}
.empty {
  padding: 28px 16px;
  color: var(--muted);
  text-align: center;
}
.good { color: var(--good); }
.warn { color: var(--warn); }
.bad { color: var(--bad); }
@media (max-width: 1050px) {
  .metrics, .two-up { grid-template-columns: 1fr 1fr; }
  .two-up > :first-child { grid-column: 1 / -1; }
}
@media (max-width: 720px) {
  .shell { width: min(100vw - 20px, 1360px); padding-top: 12px; }
  .topbar { align-items: stretch; flex-direction: column; }
  .date-controls { display: grid; grid-template-columns: 1fr auto; }
  .date-controls input { min-width: 0; }
  .metrics, .two-up { grid-template-columns: 1fr; }
  .table-wrap { overflow-x: auto; }
}
`;

const numberFormat = new Intl.NumberFormat([], { maximumFractionDigits: 2 });

function injectStyles() {
  const element = document.createElement("style");
  element.textContent = styles;
  document.head.appendChild(element);
}

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function dateFromLocation() {
  return new URLSearchParams(window.location.search).get("date") || todayKey();
}

function fmt(value: unknown, suffix = "") {
  if (value === null || value === undefined || value === "") return "-";
  if (typeof value === "number") return `${numberFormat.format(Math.abs(value) < 1e-9 ? 0 : value)}${suffix}`;
  return String(value);
}

function fmtTime(value?: string, options: Intl.DateTimeFormatOptions = { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }) {
  if (!value) return "-";
  return new Intl.DateTimeFormat([], options).format(new Date(value));
}

function sum(points: TelemetryPoint[], key: keyof TelemetryPoint) {
  return points.reduce((total, point) => total + Number(point[key] || 0), 0);
}

function bucketTime(summary: PlannerSummary, point: TelemetryPoint) {
  const start = summary.planner_timestamp ? new Date(summary.planner_timestamp) : new Date();
  start.setMinutes(start.getMinutes() + Number(point.bucket_index || 0) * Number(summary.bucket_minutes || 15));
  return new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit" }).format(start);
}

function selectedSummary(plan: PlannerSnapshot | null): PlannerSummary {
  return plan?.summary || {};
}

function selectedTimeline(plan: PlannerSnapshot | null): TelemetryPoint[] {
  return plan?.telemetry_timeline || [];
}

function selectedBands(plan: PlannerSnapshot | null): DemandBand[] {
  return plan?.bands || [];
}

function Metric({ label, value, foot, className = "" }: { label: string; value: React.ReactNode; foot?: string; className?: string }) {
  return <div className={`metric ${className}`}>
    <span>{label}</span>
    <strong>{value}</strong>
    {foot ? <span>{foot}</span> : null}
  </div>;
}

function Sparkline({ points, summary }: { points: TelemetryPoint[]; summary: PlannerSummary }) {
  const width = 960;
  const height = 300;
  const left = 42;
  const right = 14;
  const top = 16;
  const bottom = 34;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const maxEnergy = Math.max(1, ...points.map((point) => Math.max(
    Number(point.solar_kwh || 0),
    Number(point.import_kwh || 0),
    Number(point.fixed_load_kwh || 0) + Number(point.flexible_load_kwh || 0),
    Number(point.battery_charge_kwh || 0),
    Number(point.battery_discharge_kwh || 0),
  )));
  const maxSoc = Math.max(Number(summary.battery_capacity_kwh || 0), ...points.map((point) => Number(point.battery_soc_kwh || 0)), 1);
  const step = points.length > 1 ? plotWidth / (points.length - 1) : plotWidth;
  const xFor = (index: number) => left + index * step;
  const yEnergy = (value: number) => top + plotHeight - (value / maxEnergy) * plotHeight;
  const ySoc = (value: number) => top + plotHeight - (value / maxSoc) * plotHeight;
  const socLine = points.map((point, index) => `${xFor(index)},${ySoc(Number(point.battery_soc_kwh || 0))}`).join(" ");
  const reserveLine = points.map((point, index) => `${xFor(index)},${ySoc(Number(point.reserve_target_kwh || 0))}`).join(" ");
  const barWidth = Math.max(4, Math.min(18, step * 0.62));
  const ticks = points.filter((_, index) => index % Math.max(1, Math.ceil(points.length / 8)) === 0);

  if (!points.length) return <div className="empty">No forecast timeline for this date.</div>;

  return <svg className="chart" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Energy forecast chart">
    {[0, 0.5, 1].map((fraction) => {
      const y = top + plotHeight * fraction;
      return <line key={fraction} className="axis" x1={left} y1={y} x2={width - right} y2={y} />;
    })}
    {points.map((point, index) => {
      const demand = Number(point.fixed_load_kwh || 0) + Number(point.flexible_load_kwh || 0);
      const x = xFor(index) - barWidth / 2;
      return <g key={index}>
        <rect x={x} y={yEnergy(Number(point.solar_kwh || 0))} width={barWidth} height={plotHeight + top - yEnergy(Number(point.solar_kwh || 0))} fill="#a1a1aa" opacity="0.55" />
        <rect x={x + barWidth * 0.34} y={yEnergy(Number(point.import_kwh || 0))} width={barWidth * 0.66} height={plotHeight + top - yEnergy(Number(point.import_kwh || 0))} fill="#2563eb" opacity="0.6" />
        <rect x={x + barWidth * 0.68} y={yEnergy(demand)} width={barWidth * 0.66} height={plotHeight + top - yEnergy(demand)} fill="#09090b" opacity="0.82" />
      </g>;
    })}
    <polyline points={reserveLine} fill="none" stroke="#b45309" strokeWidth="2" strokeDasharray="5 5" />
    <polyline points={socLine} fill="none" stroke="#047857" strokeWidth="3" />
    {ticks.map((point, index) => <text key={index} className="tick" x={xFor(points.indexOf(point))} y={height - 10} textAnchor="middle">{bucketTime(summary, point)}</text>)}
    <text className="tick" x={left - 8} y={top + 4} textAnchor="end">{fmt(maxEnergy)}</text>
    <text className="tick" x={left - 8} y={top + plotHeight + 4} textAnchor="end">0</text>
  </svg>;
}

function EnergyChart({ plan }: { plan: PlannerSnapshot | null }) {
  const summary = selectedSummary(plan);
  const points = selectedTimeline(plan);
  return <section className="panel">
    <div className="panel-header">
      <div>
        <h2>Future</h2>
        <p>{points.length ? `${points.length} planner buckets from ${fmtTime(summary.planner_timestamp)}` : "No selected snapshot"}</p>
      </div>
      <div className="legend">
        <span><i className="dot" style={{ background: "#a1a1aa" }} />Solar</span>
        <span><i className="dot" style={{ background: "#2563eb" }} />Import</span>
        <span><i className="dot" style={{ background: "#09090b" }} />Demand</span>
        <span><i className="dot" style={{ background: "#047857" }} />SoC</span>
      </div>
    </div>
    <div className="chart-wrap"><Sparkline points={points} summary={summary} /></div>
  </section>;
}

function Bands({ plan }: { plan: PlannerSnapshot | null }) {
  const bands = selectedBands(plan).slice().sort((left, right) => Number(right.shortfall_kwh || 0) - Number(left.shortfall_kwh || 0)).slice(0, 8);
  return <section className="panel">
    <div className="panel-header">
      <div>
        <h3>Planner Bands</h3>
        <p>{bands.length ? `${bands.length} active bands` : "No active demand bands"}</p>
      </div>
    </div>
    <div className="panel-pad stack">
      {bands.length ? bands.map((band) => {
        const target = Number(band.target_quantity_kwh || 0);
        const served = Number(band.served_quantity_kwh || 0);
        const pct = target > 0 ? Math.max(0, Math.min(100, (served / target) * 100)) : 100;
        return <div className="band" key={band.band_id}>
          <div className="band-head">
            <strong>{band.display_name || band.band_id}</strong>
            <span className={`pill ${Number(band.shortfall_kwh || 0) > 0 ? "bad" : ""}`}>{fmt(band.shortfall_kwh, " kWh short")}</span>
          </div>
          <div className="bar"><i style={{ width: `${pct}%` }} /></div>
          <span className="muted">{fmt(served, " kWh")} of {fmt(target, " kWh")} served</span>
        </div>;
      }) : <div className="empty">No demand band data in the selected snapshot.</div>}
    </div>
  </section>;
}

function HistoryTable({ history }: { history: HistoryEntry[] }) {
  return <section className="panel">
    <div className="panel-header">
      <div>
        <h3>Past Runs</h3>
        <p>{history.length ? `${history.length} runs on this date` : "No runs on this date"}</p>
      </div>
    </div>
    {history.length ? <div className="table-wrap">
      <table className="table">
        <thead>
          <tr>
            <th>Run</th>
            <th>Objective</th>
            <th>Battery</th>
            <th>Import</th>
            <th>Tesla</th>
            <th>Shortfalls</th>
          </tr>
        </thead>
        <tbody>
          {history.map((entry) => <tr key={entry.id}>
            <td>{fmtTime(entry.created_at, { hour: "2-digit", minute: "2-digit", second: "2-digit" })}</td>
            <td>{fmt(entry.summary.objective_value_czk, " CZK")}</td>
            <td>{fmt(entry.summary.battery_soc_kwh, " kWh")}</td>
            <td>{fmt(entry.summary.current_import_kwh, " kWh")}</td>
            <td>{fmt(entry.summary.current_tesla_kwh, " kWh")}</td>
            <td>{entry.snapshot.shortfalls?.length || 0}</td>
          </tr>)}
        </tbody>
      </table>
    </div> : <div className="empty">No persisted history exists for this date.</div>}
  </section>;
}

function TeslaContext({ plan }: { plan: PlannerSnapshot | null }) {
  const days = plan?.tesla_calendar_summary || [];
  return <section className="panel">
    <div className="panel-header">
      <div>
        <h3>Tesla Calendar</h3>
        <p>{days.length ? `${days.length} future days` : "No calendar data"}</p>
      </div>
    </div>
    <div className="panel-pad stack">
      {days.slice(0, 7).map((day) => <div className="band" key={day.date}>
        <div className="band-head">
          <strong>{fmtTime(`${day.date}T12:00:00`, { weekday: "short", month: "short", day: "numeric" })}</strong>
          <span className="pill">{fmt(Math.round(Number(day.confidence || 0) * 100), "%")}</span>
        </div>
        <span className="muted">{day.departure_time ? `${day.departure_time} departure, target ${fmt(day.target_soc_pct, "%")}` : "No departure"}</span>
      </div>)}
      {!days.length ? <div className="empty">No Tesla planning hints in the selected snapshot.</div> : null}
    </div>
  </section>;
}

function Metrics({ plan, latest }: { plan: PlannerSnapshot | null; latest: PlannerSnapshot | null }) {
  const summary = selectedSummary(plan);
  const timeline = selectedTimeline(plan);
  const latestSummary = selectedSummary(latest);
  const totalImport = sum(timeline, "import_kwh");
  const totalExport = sum(timeline, "export_kwh");
  const totalTesla = sum(timeline, "tesla_kwh");
  return <div className="grid metrics">
    <Metric label="Status" value={summary.planner_status || "No snapshot"} foot={fmtTime(summary.planner_timestamp)} className={summary.planner_status === "ok" ? "good" : ""} />
    <Metric label="Objective" value={fmt(summary.objective_value_czk, " CZK")} foot="selected run" />
    <Metric label="Battery" value={fmt(summary.battery_soc_kwh, " kWh")} foot={`reserve ${fmt(summary.battery_reserve_kwh, " kWh")}`} />
    <Metric label="Grid" value={summary.grid_available === false ? "Offline" : "Available"} foot={`${fmt(totalImport, " kWh")} in / ${fmt(totalExport, " kWh")} out`} />
    <Metric label="Tesla" value={fmt(totalTesla, " kWh")} foot={summary.next_tesla_day?.departure_time ? `next ${summary.next_tesla_day.departure_time}` : "no departure"} />
    <Metric label="Latest" value={fmtTime(latestSummary.planner_timestamp, { hour: "2-digit", minute: "2-digit" })} foot={fmtTime(latestSummary.planner_timestamp, { month: "short", day: "numeric" })} />
  </div>;
}

function App() {
  const [date, setDate] = useState(dateFromLocation());
  const [data, setData] = useState<DashboardResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const nextUrl = new URL(window.location.href);
    nextUrl.searchParams.set("date", date);
    window.history.replaceState({}, "", `${nextUrl.pathname}${nextUrl.search}`);
    fetch(`/api/dashboard?date=${encodeURIComponent(date)}`)
      .then((response) => {
        if (!response.ok) throw new Error(response.statusText);
        return response.json() as Promise<DashboardResponse>;
      })
      .then((payload) => {
        if (!cancelled) {
          setData(payload);
          setError(null);
        }
      })
      .catch((err: Error) => {
        if (!cancelled) setError(err.message);
      });
    return () => { cancelled = true; };
  }, [date]);

  const selectedPlan = data?.selected_plan || null;
  const latestPlan = data?.latest_plan || null;
  const dateList = useMemo(() => data?.available_dates || [], [data]);

  return <main className="shell">
    <header className="topbar">
      <div className="brand">
        <h1>Energy Scheduler</h1>
        <span>Read-only planner dashboard</span>
      </div>
      <div className="date-controls">
        <input type="date" value={date} list="available-dates" onChange={(event) => setDate(event.target.value)} />
        <datalist id="available-dates">
          {dateList.map((item) => <option key={item} value={item} />)}
        </datalist>
        <button type="button" onClick={() => setDate(todayKey())}>Today</button>
        <button type="button" className="primary" onClick={() => data?.available_dates[0] && setDate(data.available_dates[0])}>Latest</button>
      </div>
    </header>

    {error ? <section className="panel panel-pad bad">Failed to load dashboard: {error}</section> : null}
    <Metrics plan={selectedPlan} latest={latestPlan} />
    <div className="grid two-up">
      <EnergyChart plan={selectedPlan} />
      <div className="grid">
        <Bands plan={selectedPlan} />
        <TeslaContext plan={selectedPlan} />
      </div>
    </div>
    <div style={{ height: 16 }} />
    <HistoryTable history={data?.history || []} />
  </main>;
}

injectStyles();

const root = document.getElementById("root");
if (!root) throw new Error("Missing #root");
createRoot(root).render(<App />);
