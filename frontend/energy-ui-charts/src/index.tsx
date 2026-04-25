import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import { Bar, CartesianGrid, ComposedChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
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
.date-picker {
  position: relative;
}
.date-trigger {
  min-width: 178px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 14px;
}
.date-trigger small {
  color: var(--muted);
  font-weight: 500;
}
.calendar-popover {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  z-index: 20;
  width: min(360px, calc(100vw - 24px));
  border: 1px solid var(--line);
  border-radius: 10px;
  background: var(--panel);
  box-shadow: 0 18px 48px rgba(0, 0, 0, 0.14);
  padding: 12px;
}
.shortcut-row {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 6px;
  margin-bottom: 10px;
}
.shortcut-row button {
  padding: 0.5rem 0.45rem;
}
.month-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 10px;
}
.month-header strong {
  font-size: 0.92rem;
}
.month-nav {
  display: flex;
  gap: 6px;
}
.month-nav button {
  width: 32px;
  height: 32px;
  padding: 0;
}
.calendar-weekdays,
.calendar-days {
  display: grid;
  grid-template-columns: repeat(7, minmax(0, 1fr));
  gap: 4px;
}
.calendar-weekdays span {
  color: var(--muted);
  font-size: 0.72rem;
  font-weight: 600;
  text-align: center;
  padding: 4px 0;
}
.calendar-day-button {
  height: 34px;
  padding: 0;
  border-radius: 7px;
  font-size: 0.82rem;
  position: relative;
}
.calendar-day-button.outside {
  color: #a1a1aa;
  background: #fbfbfb;
}
.calendar-day-button.selected {
  background: var(--ink);
  border-color: var(--ink);
  color: white;
}
.calendar-day-button.today:not(.selected) {
  border-color: var(--ink);
}
.calendar-day-button.has-data::after {
  content: "";
  position: absolute;
  left: 50%;
  bottom: 4px;
  width: 4px;
  height: 4px;
  border-radius: 999px;
  background: currentColor;
  transform: translateX(-50%);
  opacity: 0.7;
}
.calendar-foot {
  margin-top: 10px;
  color: var(--muted);
  font-size: 0.76rem;
  line-height: 1.4;
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
  min-width: 0;
  display: grid;
  gap: 8px;
}
.chart + .chart {
  margin-top: 24px;
}
.chart-canvas {
  width: 100%;
  height: 260px;
  min-width: 0;
  min-height: 260px;
}
.chart-title-row {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  align-items: center;
  margin-bottom: 8px;
}
.chart-title-row h3 {
  margin: 0;
  font-size: 0.9rem;
}
.chart-title-row p {
  margin: 3px 0 0;
  color: var(--muted);
  font-size: 0.78rem;
}
.chart-tooltip {
  min-width: 220px;
  border: 1px solid var(--line);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.98);
  box-shadow: 0 12px 30px rgba(0, 0, 0, 0.08);
  padding: 10px 12px;
}
.chart-tooltip strong {
  display: block;
  margin-bottom: 8px;
  font-size: 0.86rem;
}
.chart-tooltip-row {
  display: flex;
  justify-content: space-between;
  gap: 18px;
  color: var(--muted);
  font-size: 0.82rem;
}
.chart-tooltip-row + .chart-tooltip-row {
  margin-top: 5px;
}
.chart-tooltip-row span:first-child {
  display: inline-flex;
  align-items: center;
  gap: 6px;
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
.axis-legend {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  margin: 16px 0 0;
  color: var(--muted);
  font-size: 0.78rem;
}
.axis-legend span {
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 3px 8px;
  background: #fcfcfc;
}
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
  .date-picker { min-width: 0; }
  .date-trigger { width: 100%; min-width: 0; }
  .calendar-popover { left: 0; right: auto; }
  .metrics, .two-up { grid-template-columns: 1fr; }
  .table-wrap { overflow-x: auto; }
  .chart-canvas { height: 230px; min-height: 230px; }
  .chart-title-row { align-items: start; flex-direction: column; }
}
`;

const numberFormat = new Intl.NumberFormat([], { maximumFractionDigits: 2 });
const VICTRON_COLORS = {
  solar: "#f2c94c",
  import: "#d64545",
  baseLoad: "#52525b",
  flexibleLoad: "#111827",
  battery: "#2f80ed",
  export: "#10b981",
};

function injectStyles() {
  const element = document.createElement("style");
  element.textContent = styles;
  document.head.appendChild(element);
}

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function localDate(dateKeyValue: string) {
  return new Date(`${dateKeyValue}T12:00:00`);
}

function keyFromDate(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function addDays(dateKeyValue: string, count: number) {
  const date = localDate(dateKeyValue);
  date.setDate(date.getDate() + count);
  return keyFromDate(date);
}

function addMonths(date: Date, count: number) {
  const next = new Date(date);
  next.setMonth(next.getMonth() + count, 1);
  return next;
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

function fmtDateKey(dateKeyValue: string, options: Intl.DateTimeFormatOptions = { month: "short", day: "numeric", year: "numeric" }) {
  return new Intl.DateTimeFormat([], options).format(localDate(dateKeyValue));
}

function sum(points: TelemetryPoint[], key: keyof TelemetryPoint) {
  return points.reduce((total, point) => total + Number(point[key] || 0), 0);
}

function bucketTime(summary: PlannerSummary, point: TelemetryPoint) {
  const start = summary.planner_timestamp ? new Date(summary.planner_timestamp) : new Date();
  start.setMinutes(start.getMinutes() + Number(point.bucket_index || 0) * Number(summary.bucket_minutes || 15));
  return new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit" }).format(start);
}

function chartRows(points: TelemetryPoint[], summary: PlannerSummary) {
  return points.map((point) => ({
    ...point,
    time: bucketTime(summary, point),
    grid_import_kwh: Number(point.import_kwh || 0),
    grid_export_kwh: Number(point.export_kwh || 0),
    base_load_kwh: Number(point.fixed_load_kwh || 0),
    flexible_load_kwh: Number(point.flexible_load_kwh || 0),
  }));
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

type ChartSeries = {
  key: string;
  label: string;
  color: string;
};

function EnergyFlowChart({
  title,
  subtitle,
  points,
  summary,
  series,
  chartId,
}: {
  title: string;
  subtitle: string;
  points: TelemetryPoint[];
  summary: PlannerSummary;
  series: ChartSeries[];
  chartId: string;
}) {
  if (!points.length) return <div className="empty">No forecast timeline for this date.</div>;
  const data = chartRows(points, summary);

  return <div className="chart" data-chart={chartId} role="img" aria-label={`${title} chart`}>
    <div className="chart-title-row">
      <div>
        <h3>{title}</h3>
        <p>{subtitle}</p>
      </div>
      <div className="legend">
        {series.map((item) => <span key={item.key}><i className="dot" style={{ background: item.color }} />{item.label}</span>)}
      </div>
    </div>
    <div className="chart-canvas">
    <ResponsiveContainer width="100%" height="100%" minWidth={0} minHeight={260}>
      <ComposedChart data={data} margin={{ top: 6, right: 18, bottom: 8, left: 22 }} barGap={1} barCategoryGap={2}>
        <CartesianGrid stroke="var(--line)" vertical={false} />
        <XAxis dataKey="time" tick={{ fill: "var(--muted)", fontSize: 11 }} tickLine={false} axisLine={{ stroke: "var(--line)" }} interval={5} />
        <YAxis
          yAxisId="energy"
          tick={{ fill: "var(--muted)", fontSize: 11 }}
          tickLine={false}
          axisLine={false}
          width={58}
          label={{ value: "kWh / bucket", angle: -90, position: "insideLeft", offset: -8, fill: "var(--muted)", fontSize: 11 }}
        />
        <Tooltip content={<ChartTooltip />} cursor={{ fill: "rgba(9, 9, 11, 0.04)" }} />
        {series.map((item) => (
          <Bar
            key={item.key}
            yAxisId="energy"
            dataKey={item.key}
            name={item.label}
            fill={item.color}
            opacity={0.82}
            radius={[3, 3, 0, 0]}
            barSize={10}
            stackId="energy"
          />
        ))}
      </ComposedChart>
    </ResponsiveContainer>
    </div>
  </div>;
}

function ChartTooltip(props: { active?: boolean; payload?: Array<{ name?: string; value?: number; color?: string }>; label?: string }) {
  if (!props.active || !props.payload?.length) return null;
  return <div className="chart-tooltip">
    <strong>{props.label}</strong>
    {props.payload.map((item) => <div className="chart-tooltip-row" key={item.name}>
      <span><i className="dot" style={{ background: item.color || "var(--muted)" }} />{item.name}</span>
      <b>{fmt(item.value, " kWh")}</b>
    </div>)}
  </div>;
}

function EnergyChart({ plan }: { plan: PlannerSnapshot | null }) {
  const summary = selectedSummary(plan);
  const points = selectedTimeline(plan);
  const generationSeries = [
    { key: "solar_kwh", label: "Solar", color: VICTRON_COLORS.solar },
    { key: "battery_discharge_kwh", label: "Battery discharge", color: VICTRON_COLORS.battery },
    { key: "grid_import_kwh", label: "Grid import", color: VICTRON_COLORS.import },
  ];
  const useSeries = [
    { key: "base_load_kwh", label: "Base load", color: VICTRON_COLORS.baseLoad },
    { key: "flexible_load_kwh", label: "Flexible / Tesla", color: VICTRON_COLORS.flexibleLoad },
    { key: "battery_charge_kwh", label: "Battery charge", color: VICTRON_COLORS.battery },
    { key: "grid_export_kwh", label: "Grid export", color: VICTRON_COLORS.export },
  ];
  return <section className="panel">
    <div className="panel-header">
      <div>
        <h2>Future</h2>
        <p>{points.length ? `${points.length} planner buckets from ${fmtTime(summary.planner_timestamp)}` : "No selected snapshot"}</p>
      </div>
    </div>
    <div className="chart-wrap">
      <EnergyFlowChart
        title="Electricity Generation"
        subtitle="Where usable energy comes from"
        points={points}
        summary={summary}
        series={generationSeries}
        chartId="generation"
      />
      <EnergyFlowChart
        title="Electricity Use"
        subtitle="Where planned energy goes"
        points={points}
        summary={summary}
        series={useSeries}
        chartId="use"
      />
      <div className="axis-legend" aria-label="Chart axis units">
        <span>Both charts use kWh per planner bucket</span>
        <span>Supply and use are split so grid import is not visually confused with demand</span>
      </div>
    </div>
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

function DatePicker({
  value,
  availableDates,
  onChange,
}: {
  value: string;
  availableDates: string[];
  onChange: (value: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [visibleMonth, setVisibleMonth] = useState(() => {
    const selected = localDate(value);
    return new Date(selected.getFullYear(), selected.getMonth(), 1, 12, 0, 0, 0);
  });
  const today = todayKey();
  const availableSet = useMemo(() => new Set(availableDates), [availableDates]);

  useEffect(() => {
    const selected = localDate(value);
    setVisibleMonth(new Date(selected.getFullYear(), selected.getMonth(), 1, 12, 0, 0, 0));
  }, [value]);

  const choose = (next: string) => {
    onChange(next);
    setOpen(false);
  };
  const firstDayOffset = (visibleMonth.getDay() + 6) % 7;
  const gridStart = new Date(visibleMonth);
  gridStart.setDate(visibleMonth.getDate() - firstDayOffset);
  const days = Array.from({ length: 42 }, (_, index) => {
    const date = new Date(gridStart);
    date.setDate(gridStart.getDate() + index);
    return date;
  });

  return <div className="date-picker">
    <button type="button" className="date-trigger" onClick={() => setOpen((current) => !current)} aria-expanded={open}>
      <span>{fmtDateKey(value)}</span>
      <small>Change date</small>
    </button>
    {open ? <div className="calendar-popover">
      <div className="shortcut-row">
        <button type="button" onClick={() => choose(addDays(today, -1))}>Yesterday</button>
        <button type="button" className="primary" onClick={() => choose(today)}>Today</button>
        <button type="button" onClick={() => choose(addDays(today, 1))}>Tomorrow</button>
      </div>
      <div className="month-header">
        <strong>{new Intl.DateTimeFormat([], { month: "long", year: "numeric" }).format(visibleMonth)}</strong>
        <div className="month-nav">
          <button type="button" aria-label="Previous month" onClick={() => setVisibleMonth((current) => addMonths(current, -1))}>‹</button>
          <button type="button" aria-label="Next month" onClick={() => setVisibleMonth((current) => addMonths(current, 1))}>›</button>
        </div>
      </div>
      <div className="calendar-weekdays">
        {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((day) => <span key={day}>{day}</span>)}
      </div>
      <div className="calendar-days">
        {days.map((day) => {
          const key = keyFromDate(day);
          const outside = day.getMonth() !== visibleMonth.getMonth();
          const selected = key === value;
          const currentToday = key === today;
          const hasData = availableSet.has(key);
          return <button
            type="button"
            key={key}
            className={`calendar-day-button ${outside ? "outside" : ""} ${selected ? "selected" : ""} ${currentToday ? "today" : ""} ${hasData ? "has-data" : ""}`.trim()}
            onClick={() => choose(key)}
          >
            {day.getDate()}
          </button>;
        })}
      </div>
      <p className="calendar-foot">Small dots mark dates with saved planner runs.</p>
    </div> : null}
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
        <DatePicker value={date} availableDates={dateList} onChange={setDate} />
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
