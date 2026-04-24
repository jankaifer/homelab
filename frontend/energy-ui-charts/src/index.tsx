import React from "react";
import { flushSync } from "react-dom";
import { createRoot } from "react-dom/client";
import {
  Area,
  Bar,
  BarChart,
  CartesianGrid,
  ComposedChart,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

const COLORS = {
  solar: "#d08b3c",
  import: "#4168ad",
  discharge: "#255d49",
  baseLoad: "#33483b",
  flexible: "#111111",
  charge: "#b96a31",
  export: "#a5481f",
  curtail: "#a8a18f",
  reserve: "#b96a31",
  emergency: "#a5481f",
  tesla: "#111111",
  grid: "rgba(216, 209, 194, 0.9)",
  axis: "#617166",
  tooltipBorder: "rgba(216, 209, 194, 0.92)",
  tooltipBackground: "rgba(255, 252, 246, 0.98)",
};

const roots = new WeakMap();

function fmtNumber(value, digits = 2) {
  return Number(value || 0).toFixed(digits);
}

function fmtDetailed(value) {
  return `${fmtNumber(value)} kWh`;
}

function fmtPrice(value) {
  return `${fmtNumber(value)} CZK/kWh`;
}

function fmtMoney(value) {
  return `${fmtNumber(value)} CZK`;
}

function ensureRoot(target) {
  let root = roots.get(target);
  if (!root) {
    root = createRoot(target);
    roots.set(target, root);
  }
  return root;
}

function mountChart(target, element) {
  const root = ensureRoot(target);
  try {
    flushSync(() => {
      root.render(element);
    });
  } catch (error) {
    console.error("Energy chart render failed", error);
    target.innerHTML = "";
    const fallback = document.createElement("div");
    fallback.style.minHeight = "220px";
    fallback.style.display = "grid";
    fallback.style.placeItems = "center";
    fallback.style.color = "var(--muted, #617166)";
    fallback.style.font = '12px "Avenir Next", "Segoe UI", sans-serif';
    fallback.textContent = "Chart rendering failed.";
    target.appendChild(fallback);
  }
}

function renderIntoTarget(target, element) {
  mountChart(
    target,
    React.createElement(
      "div",
      {
        style: {
          width: "100%",
          height: "100%",
          minHeight: "inherit",
        },
      },
      element,
    ),
  );
}

function EmptyState({ message, height }) {
  return React.createElement(
    "div",
    {
      style: {
        minHeight: `${height}px`,
        display: "grid",
        placeItems: "center",
        color: "var(--muted, #617166)",
        font: '12px "Avenir Next", "Segoe UI", sans-serif',
      },
    },
    message,
  );
}

function TooltipShell({ label, rows, footer }) {
  return React.createElement(
    "div",
    {
      style: {
        minWidth: "240px",
        maxWidth: "340px",
        padding: "0.95rem 1rem",
        borderRadius: "16px",
        border: `1px solid ${COLORS.tooltipBorder}`,
        background: COLORS.tooltipBackground,
        boxShadow: "0 18px 44px rgba(21, 33, 25, 0.16)",
      },
    },
    React.createElement("div", { style: { marginBottom: "0.65rem", fontWeight: 700, fontSize: "0.98rem", color: "var(--ink, #152119)" } }, label),
    React.createElement(
      "div",
      { style: { display: "grid", gap: "0.4rem" } },
      rows.map((row) =>
        React.createElement(
          "div",
          {
            key: row.label,
            style: {
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              gap: "0.8rem",
              fontSize: "0.88rem",
            },
          },
          React.createElement(
            "span",
            { style: { display: "inline-flex", alignItems: "center", gap: "0.45rem", color: "var(--muted, #617166)" } },
            React.createElement("span", {
              style: {
                width: "0.72rem",
                height: "0.72rem",
                borderRadius: "999px",
                background: row.color,
                flex: "0 0 auto",
              },
            }),
            row.label,
          ),
          React.createElement("strong", null, row.value),
        ),
      ),
    ),
    footer
      ? React.createElement(
          "div",
          {
            style: {
              marginTop: "0.75rem",
              paddingTop: "0.65rem",
              borderTop: "1px solid rgba(216, 209, 194, 0.86)",
              color: "var(--muted, #617166)",
              fontSize: "0.82rem",
              lineHeight: 1.45,
            },
          },
          footer,
        )
      : null,
  );
}

function FlowTooltip({ active, payload }) {
  if (!active || !payload?.length) return null;
  const point = payload[0].payload;
  const importCost = Number(point.import_kwh || 0) * Number(point.import_price_czk_per_kwh || 0);
  const exportRevenue = Number(point.export_kwh || 0) * Number(point.export_price_czk_per_kwh || 0);
  return React.createElement(TooltipShell, {
    label: point.hour_label,
    rows: [
      { label: "Solar", value: fmtDetailed(point.solar_kwh), color: COLORS.solar },
      { label: "Grid import", value: fmtDetailed(point.import_kwh), color: COLORS.import },
      { label: "Battery discharge", value: fmtDetailed(point.battery_discharge_kwh), color: COLORS.discharge },
      { label: "Base load", value: fmtDetailed(point.fixed_load_kwh), color: COLORS.baseLoad },
      { label: "Flexible load", value: fmtDetailed(point.flexible_load_kwh), color: COLORS.flexible },
      { label: "Battery charge", value: fmtDetailed(point.battery_charge_kwh), color: COLORS.charge },
      { label: "Grid export", value: fmtDetailed(point.export_kwh), color: COLORS.export },
      { label: "Curtailment", value: fmtDetailed(point.curtail_kwh), color: COLORS.curtail },
      { label: "Import price", value: fmtPrice(point.import_price_czk_per_kwh), color: "#d8d1c2" },
      { label: "Export price", value: fmtPrice(point.export_price_czk_per_kwh), color: "#d8d1c2" },
    ],
    footer: `Supply ${fmtDetailed(point.supply_kwh)} vs use ${fmtDetailed(point.use_kwh)}. Drift ${fmtDetailed(point.net_balance_kwh)}. Market delta ${fmtMoney(exportRevenue - importCost)} for this hour.`,
  });
}

function BatteryTooltip({ active, payload }) {
  if (!active || !payload?.length) return null;
  const point = payload[0].payload;
  const reserveMargin = Number(point.battery_soc_kwh || 0) - Number(point.reserve_target_kwh || 0);
  const emergencyMargin = Number(point.battery_soc_kwh || 0) - Number(point.emergency_floor_kwh || 0);
  return React.createElement(TooltipShell, {
    label: point.hour_label,
    rows: [
      { label: "Battery SoC", value: fmtDetailed(point.battery_soc_kwh), color: COLORS.discharge },
      { label: "Reserve target", value: fmtDetailed(point.reserve_target_kwh), color: COLORS.reserve },
      { label: "Emergency floor", value: fmtDetailed(point.emergency_floor_kwh), color: COLORS.emergency },
      { label: "Battery charge", value: fmtDetailed(point.battery_charge_kwh), color: COLORS.charge },
      { label: "Battery discharge", value: fmtDetailed(point.battery_discharge_kwh), color: COLORS.import },
      { label: "Import price", value: fmtPrice(point.import_price_czk_per_kwh), color: "#d8d1c2" },
      { label: "Export price", value: fmtPrice(point.export_price_czk_per_kwh), color: "#d8d1c2" },
    ],
    footer: `${fmtDetailed(point.battery_soc_kwh)} stored at the end of this hour. Reserve margin ${fmtDetailed(reserveMargin)}. Emergency margin ${fmtDetailed(emergencyMargin)}.`,
  });
}

function TeslaTooltip({ active, payload }) {
  if (!active || !payload?.length) return null;
  const point = payload[0].payload;
  const flexibleLoad = Number(point.flexible_load_kwh || 0);
  const teslaLoad = Number(point.tesla_kwh || 0);
  const teslaShare = flexibleLoad > 0 ? (teslaLoad / flexibleLoad) * 100 : 0;
  return React.createElement(TooltipShell, {
    label: point.hour_label,
    rows: [
      { label: "Tesla charging", value: fmtDetailed(point.tesla_kwh), color: COLORS.tesla },
      { label: "Flexible load total", value: fmtDetailed(point.flexible_load_kwh), color: COLORS.tesla },
      { label: "Solar", value: fmtDetailed(point.solar_kwh), color: COLORS.solar },
      { label: "Grid import", value: fmtDetailed(point.import_kwh), color: COLORS.import },
      { label: "Battery discharge", value: fmtDetailed(point.battery_discharge_kwh), color: COLORS.discharge },
      { label: "Import price", value: fmtPrice(point.import_price_czk_per_kwh), color: "#d8d1c2" },
      { label: "Export price", value: fmtPrice(point.export_price_czk_per_kwh), color: "#d8d1c2" },
    ],
    footer: `Tesla is ${teslaShare.toFixed(0)}% of flexible demand in this hour. Importing this hour costs about ${fmtMoney(Number(point.tesla_kwh || 0) * Number(point.import_price_czk_per_kwh || 0))} if it all comes from the grid.`,
  });
}

function sharedChartProps(height) {
  return {
    width: "100%",
    height,
  };
}

function FlowChart({ data }) {
  if (!data?.length) {
    return React.createElement(EmptyState, { message: "No timeline data yet.", height: 400 });
  }
  const chartData = data.map((point) => ({
    ...point,
    base_load_neg: -Number(point.fixed_load_kwh || 0),
    flexible_load_neg: -Number(point.flexible_load_kwh || 0),
    battery_charge_neg: -Number(point.battery_charge_kwh || 0),
    export_neg: -Number(point.export_kwh || 0),
    curtail_neg: -Number(point.curtail_kwh || 0),
  }));
  const maxAbs = Math.max(
    0.5,
    ...chartData.map((point) => Math.max(Math.abs(point.supply_kwh || 0), Math.abs(point.use_kwh || 0))),
  );
  return React.createElement(
    ResponsiveContainer,
    sharedChartProps(400),
    React.createElement(
      ComposedChart,
      { data: chartData, margin: { top: 24, right: 24, bottom: 18, left: 12 }, barCategoryGap: "22%" },
      React.createElement(CartesianGrid, { stroke: COLORS.grid, vertical: false }),
      React.createElement(XAxis, { dataKey: "bucket_label", tick: { fill: COLORS.axis, fontSize: 12 }, tickMargin: 10, axisLine: false, tickLine: false }),
      React.createElement(YAxis, {
        tick: { fill: COLORS.axis, fontSize: 12 },
        tickFormatter: (value) => fmtNumber(value, 1),
        domain: [-maxAbs, maxAbs],
        axisLine: false,
        tickLine: false,
        width: 56,
      }),
      React.createElement(ReferenceLine, { y: 0, stroke: COLORS.axis, strokeWidth: 1.2 }),
      React.createElement(Tooltip, { content: React.createElement(FlowTooltip, null), cursor: { fill: "rgba(37, 93, 73, 0.08)" } }),
      React.createElement(Bar, { dataKey: "solar_kwh", stackId: "supply", fill: COLORS.solar, radius: [8, 8, 0, 0], maxBarSize: 26 }),
      React.createElement(Bar, { dataKey: "import_kwh", stackId: "supply", fill: COLORS.import, radius: [8, 8, 0, 0], maxBarSize: 26 }),
      React.createElement(Bar, { dataKey: "battery_discharge_kwh", stackId: "supply", fill: COLORS.discharge, radius: [8, 8, 0, 0], maxBarSize: 26 }),
      React.createElement(Bar, { dataKey: "base_load_neg", stackId: "use", fill: COLORS.baseLoad, radius: [0, 0, 8, 8], maxBarSize: 26 }),
      React.createElement(Bar, { dataKey: "flexible_load_neg", stackId: "use", fill: COLORS.flexible, radius: [0, 0, 8, 8], maxBarSize: 26 }),
      React.createElement(Bar, { dataKey: "battery_charge_neg", stackId: "use", fill: COLORS.charge, radius: [0, 0, 8, 8], maxBarSize: 26 }),
      React.createElement(Bar, { dataKey: "export_neg", stackId: "use", fill: COLORS.export, radius: [0, 0, 8, 8], maxBarSize: 26 }),
      React.createElement(Bar, { dataKey: "curtail_neg", stackId: "use", fill: COLORS.curtail, radius: [0, 0, 8, 8], maxBarSize: 26 }),
    ),
  );
}

function BatteryChart({ data, summary }) {
  if (!data?.length) {
    return React.createElement(EmptyState, { message: "No battery timeline data yet.", height: 360 });
  }
  const maxY = Math.max(
    Number(summary?.battery_capacity_kwh || 0),
    ...data.map((point) => Math.max(point.battery_soc_kwh || 0, point.reserve_target_kwh || 0, point.emergency_floor_kwh || 0)),
    1,
  );
  return React.createElement(
    ResponsiveContainer,
    sharedChartProps(360),
    React.createElement(
      ComposedChart,
      { data, margin: { top: 24, right: 24, bottom: 16, left: 12 } },
      React.createElement(CartesianGrid, { stroke: COLORS.grid, vertical: false }),
      React.createElement(XAxis, { dataKey: "bucket_label", tick: { fill: COLORS.axis, fontSize: 12 }, tickMargin: 10, axisLine: false, tickLine: false }),
      React.createElement(YAxis, {
        tick: { fill: COLORS.axis, fontSize: 12 },
        tickFormatter: (value) => fmtNumber(value, 1),
        domain: [0, maxY],
        axisLine: false,
        tickLine: false,
        width: 56,
      }),
      React.createElement(Tooltip, { content: React.createElement(BatteryTooltip, null), cursor: { stroke: "rgba(37, 93, 73, 0.5)", strokeDasharray: "5 5" } }),
      React.createElement(Area, { type: "monotone", dataKey: "battery_soc_kwh", stroke: COLORS.discharge, fill: "rgba(37, 93, 73, 0.14)", strokeWidth: 3 }),
      React.createElement(Line, { type: "monotone", dataKey: "reserve_target_kwh", stroke: COLORS.reserve, strokeWidth: 2.4, strokeDasharray: "7 5", dot: false }),
      React.createElement(Line, { type: "monotone", dataKey: "emergency_floor_kwh", stroke: COLORS.emergency, strokeWidth: 2.4, strokeDasharray: "4 5", dot: false }),
    ),
  );
}

function TeslaChart({ data }) {
  if (!data?.length || data.every((point) => Number(point.tesla_kwh || 0) < 0.01)) {
    return React.createElement(EmptyState, { message: "No Tesla charging is planned in the next 24 hours.", height: 320 });
  }
  const maxY = Math.max(0.5, ...data.map((point) => Number(point.tesla_kwh || 0)));
  return React.createElement(
    ResponsiveContainer,
    sharedChartProps(320),
    React.createElement(
      BarChart,
      { data, margin: { top: 24, right: 24, bottom: 16, left: 12 }, barCategoryGap: "26%" },
      React.createElement(CartesianGrid, { stroke: COLORS.grid, vertical: false }),
      React.createElement(XAxis, { dataKey: "bucket_label", tick: { fill: COLORS.axis, fontSize: 12 }, tickMargin: 10, axisLine: false, tickLine: false }),
      React.createElement(YAxis, {
        tick: { fill: COLORS.axis, fontSize: 12 },
        tickFormatter: (value) => fmtNumber(value, 1),
        domain: [0, maxY],
        axisLine: false,
        tickLine: false,
        width: 56,
      }),
      React.createElement(Tooltip, { content: React.createElement(TeslaTooltip, null), cursor: { fill: "rgba(37, 93, 73, 0.08)" } }),
      React.createElement(Bar, { dataKey: "tesla_kwh", fill: COLORS.tesla, radius: [8, 8, 0, 0], maxBarSize: 28 }),
    ),
  );
}

function renderChart(target, element) {
  if (!target) return;
  renderIntoTarget(target, element);
}

const EnergyCharts = {
  renderFlowChart(target, data, summary) {
    renderChart(target, React.createElement(FlowChart, { data, summary }));
  },
  renderBatteryChart(target, data, summary) {
    renderChart(target, React.createElement(BatteryChart, { data, summary }));
  },
  renderTeslaChart(target, data, summary) {
    renderChart(target, React.createElement(TeslaChart, { data, summary }));
  },
};

globalThis.EnergyCharts = EnergyCharts;
