export type PlannerSummary = {
  planner_status?: string;
  planner_timestamp?: string;
  objective_value_czk?: number;
  bucket_minutes?: number;
  horizon_buckets?: number;
  battery_soc_kwh?: number;
  battery_capacity_kwh?: number;
  battery_reserve_kwh?: number;
  battery_emergency_floor_kwh?: number;
  current_import_kwh?: number;
  current_export_kwh?: number;
  current_flexible_load_kwh?: number;
  current_tesla_kwh?: number;
  grid_available?: boolean;
  next_tesla_day?: TeslaCalendarDay | null;
};

export type TelemetryPoint = {
  bucket_index: number;
  battery_soc_kwh?: number;
  battery_charge_kwh?: number;
  battery_discharge_kwh?: number;
  reserve_target_kwh?: number;
  emergency_floor_kwh?: number;
  import_kwh?: number;
  export_kwh?: number;
  curtail_kwh?: number;
  solar_kwh?: number;
  fixed_load_kwh?: number;
  flexible_load_kwh?: number;
  tesla_kwh?: number;
  import_price_czk_per_kwh?: number;
  export_price_czk_per_kwh?: number;
};

export type DemandBand = {
  band_id: string;
  asset_id: string;
  display_name?: string;
  required_level?: boolean;
  deadline_index?: number;
  target_quantity_kwh?: number;
  served_quantity_kwh?: number;
  shortfall_kwh?: number;
  scenario_probability?: number;
  confidence?: number;
  metadata?: Record<string, unknown>;
};

export type TeslaCalendarDay = {
  date: string;
  mode?: string;
  departure_time?: string | null;
  target_soc_pct?: number | null;
  confidence?: number;
};

export type PlannerSnapshot = {
  created_at?: string;
  summary?: PlannerSummary;
  telemetry_timeline?: TelemetryPoint[];
  bands?: DemandBand[];
  tesla_calendar_summary?: TeslaCalendarDay[];
  shortfalls?: Array<Record<string, unknown>>;
  battery_plan?: Array<Record<string, unknown>>;
  band_allocations?: Array<Record<string, unknown>>;
  scenario_summary?: Array<Record<string, unknown>>;
};

export type HistoryEntry = {
  id: string;
  path: string;
  created_at: string;
  date: string | null;
  summary: PlannerSummary;
  snapshot: PlannerSnapshot;
};

export type DashboardResponse = {
  selected_date: string;
  selected_plan: PlannerSnapshot | null;
  latest_plan: PlannerSnapshot | null;
  history: HistoryEntry[];
  available_dates: string[];
};
