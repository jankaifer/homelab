import { readdirSync } from "node:fs";
import { join } from "node:path";
import type { DashboardResponse, HistoryEntry, PlannerSnapshot } from "./shared";

type ServerOptions = {
  configPath: string;
  host: string;
  port: number;
};

type RuntimeConfig = {
  runtime?: {
    state_dir?: string;
  };
};

const DEFAULT_STATE_DIR = "/var/lib/energy-scheduler";
const APP_JS_PATH = process.env.ENERGY_UI_APP_JS || join(import.meta.dir, "../../../src/energy_scheduler/ui_static/app.js");

function parseArgs(argv: string[]): ServerOptions {
  const options: ServerOptions = {
    configPath: "",
    host: "127.0.0.1",
    port: 8787,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--config") options.configPath = argv[++index] || "";
    else if (arg === "--host") options.host = argv[++index] || options.host;
    else if (arg === "--port") options.port = Number(argv[++index] || options.port);
    else if (arg === "--help" || arg === "-h") {
      console.log("Usage: bun server.ts --config CONFIG [--host HOST] [--port PORT]");
      process.exit(0);
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (!options.configPath) {
    throw new Error("--config is required");
  }
  return options;
}

async function readJsonFile<T>(path: string): Promise<T | null> {
  const file = Bun.file(path);
  if (!(await file.exists())) return null;
  return await file.json() as T;
}

function snapshotTimestamp(snapshot: PlannerSnapshot | null): string {
  return String(snapshot?.created_at || snapshot?.summary?.planner_timestamp || "");
}

function isoDate(value: string): string | null {
  if (!value) return null;
  const date = new Date(value);
  if (!Number.isNaN(date.getTime())) return date.toISOString().slice(0, 10);
  return value.length >= 10 ? value.slice(0, 10) : null;
}

function snapshotDate(snapshot: PlannerSnapshot | null): string | null {
  return isoDate(snapshotTimestamp(snapshot));
}

function historyPaths(stateDir: string): string[] {
  const historyDir = join(stateDir, "history");
  try {
    return readdirSync(historyDir)
      .filter((name) => name.endsWith(".json"))
      .sort()
      .reverse()
      .map((name) => join(historyDir, name));
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? String((error as { code?: unknown }).code) : "";
    if (code === "ENOENT") return [];
    throw error;
  }
}

async function historyEntry(path: string): Promise<HistoryEntry | null> {
  const snapshot = await readJsonFile<PlannerSnapshot>(path);
  if (!snapshot) return null;
  const createdAt = snapshotTimestamp(snapshot);
  const name = path.split("/").at(-1) || path;
  return {
    id: name.replace(/\.json$/, ""),
    path: name,
    created_at: createdAt,
    date: isoDate(createdAt),
    summary: snapshot.summary || {},
    snapshot,
  };
}

async function historyForDate(stateDir: string, date: string, limit = 96): Promise<HistoryEntry[]> {
  const entries = await Promise.all(historyPaths(stateDir).map(historyEntry));
  return entries
    .filter((entry): entry is HistoryEntry => Boolean(entry) && entry.date === date)
    .sort((left, right) => right.created_at.localeCompare(left.created_at))
    .slice(0, limit);
}

async function latestPlan(stateDir: string): Promise<PlannerSnapshot | null> {
  return await readJsonFile<PlannerSnapshot>(join(stateDir, "latest-plan.json"));
}

async function availableDates(stateDir: string, latest: PlannerSnapshot | null): Promise<string[]> {
  const entries = await Promise.all(historyPaths(stateDir).map(historyEntry));
  const dates = new Set<string>();
  for (const entry of entries) {
    if (entry?.date) dates.add(entry.date);
  }
  const latestDate = snapshotDate(latest);
  if (latestDate) dates.add(latestDate);
  return [...dates].sort().reverse().slice(0, 90);
}

async function dashboard(stateDir: string, date: string | null): Promise<DashboardResponse> {
  const today = new Date().toISOString().slice(0, 10);
  const selectedDate = date || today;
  const latest = await latestPlan(stateDir);
  const history = await historyForDate(stateDir, selectedDate);
  const selectedPlan = history[0]?.snapshot || (snapshotDate(latest) === selectedDate ? latest : null);
  return {
    selected_date: selectedDate,
    selected_plan: selectedPlan,
    latest_plan: latest,
    history,
    available_dates: await availableDates(stateDir, latest),
  };
}

function html(): Response {
  return new Response(`<!doctype html>
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
</html>`, { headers: { "content-type": "text/html; charset=utf-8" } });
}

function json(payload: unknown, status = 200): Response {
  return Response.json(payload, {
    status,
    headers: {
      "cache-control": "no-store",
    },
  });
}

async function main() {
  const options = parseArgs(Bun.argv.slice(2));
  const config = await readJsonFile<RuntimeConfig>(options.configPath);
  const stateDir = config?.runtime?.state_dir || DEFAULT_STATE_DIR;
  const server = Bun.serve({
    hostname: options.host,
    port: options.port,
    async fetch(request) {
      try {
        const url = new URL(request.url);
        if (url.pathname === "/" || url.pathname === "/dashboard") return html();
        if (url.pathname === "/favicon.ico") return new Response(null, { status: 204 });
        if (url.pathname === "/app.js") {
          const app = Bun.file(APP_JS_PATH);
          if (!(await app.exists())) return json({ error: `Missing app bundle at ${APP_JS_PATH}` }, 404);
          return new Response(app, {
            headers: {
              "content-type": "application/javascript; charset=utf-8",
              "cache-control": "no-store",
            },
          });
        }
        if (url.pathname === "/api/dashboard") return json(await dashboard(stateDir, url.searchParams.get("date")));
        if (url.pathname === "/api/live/plan") return json(await latestPlan(stateDir));
        if (url.pathname === "/api/live/summary") return json({ summary: (await latestPlan(stateDir))?.summary || {} });
        if (url.pathname === "/api/history") {
          const date = url.searchParams.get("date") || new Date().toISOString().slice(0, 10);
          return json({ date, history: await historyForDate(stateDir, date) });
        }
        if (url.pathname === "/api/history/dates") return json({ dates: await availableDates(stateDir, await latestPlan(stateDir)) });
        return json({ error: "Not found" }, 404);
      } catch (error) {
        return json({ error: error instanceof Error ? error.message : String(error) }, 400);
      }
    },
  });
  console.log(`Energy scheduler UI listening on http://${server.hostname}:${server.port}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
