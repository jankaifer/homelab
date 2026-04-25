#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${ROOT_DIR}/output/playwright/energy-ui"
URL="http://127.0.0.1:8790/"
PWCLI=(npx --yes --package @playwright/cli playwright-cli)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      URL="$2"
      shift 2
      ;;
    --out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "${OUT_DIR}" "${ROOT_DIR}/.playwright-cli"

desktop_config="$(mktemp)"
mobile_config="$(mktemp)"
trap 'rm -f "${desktop_config}" "${mobile_config}"' EXIT

cat >"${desktop_config}" <<'EOF'
{
  "browser": {
    "launchOptions": { "headless": true },
    "contextOptions": { "viewport": { "width": 1440, "height": 1100 } }
  }
}
EOF

cat >"${mobile_config}" <<'EOF'
{
  "browser": {
    "launchOptions": { "headless": true },
    "contextOptions": {
      "viewport": { "width": 390, "height": 844 },
      "isMobile": true,
      "hasTouch": true,
      "deviceScaleFactor": 2
    }
  }
}
EOF

capture_screenshot() {
  local session="$1"
  local destination="$2"
  local before
  before="$(ls -1t "${ROOT_DIR}"/.playwright-cli/page-*.png 2>/dev/null | head -n1 || true)"
  "${PWCLI[@]}" --session "${session}" screenshot >/dev/null
  local after
  after="$(ls -1t "${ROOT_DIR}"/.playwright-cli/page-*.png 2>/dev/null | head -n1 || true)"
  if [[ -z "${after}" || "${after}" == "${before}" ]]; then
    echo "Failed to capture screenshot for ${destination}" >&2
    exit 1
  fi
  cp "${after}" "${destination}"
}

session_eval() {
  local session="$1"
  local expr="$2"
  "${PWCLI[@]}" --session "${session}" eval "${expr}"
}

assert_dashboard() {
  local session="$1"
  local output
  output="$("${PWCLI[@]}" --session "${session}" eval '() => ({
    title: document.querySelector("h1")?.textContent || "",
    hasDate: Boolean(document.querySelector(".date-trigger")),
    chartCount: document.querySelectorAll(".chart svg").length,
    hasHistory: Boolean(document.querySelector("table.table") || document.body.textContent.includes("No persisted history")),
    hasWorkbench: document.body.textContent.includes("Workbench"),
    hasEditor: document.body.textContent.includes("Scenario editor")
  })')"
  RESULT_TEXT="${output}" python3 - <<'PY'
import json
import os
import re

text = os.environ["RESULT_TEXT"]
match = re.search(r'### Result\s*(.*?)\s*### Ran', text, re.S)
if not match:
    raise SystemExit("Missing Playwright eval result")
data = json.loads(match.group(1))
if data["title"] != "Energy Scheduler":
    raise SystemExit(f"Unexpected title: {data['title']}")
for key in ("hasDate", "hasHistory"):
    if not data[key]:
        raise SystemExit(f"Dashboard assertion failed: {key}")
if data["chartCount"] < 2:
    raise SystemExit(f"Expected split generation/use charts, got {data['chartCount']}")
if data["hasWorkbench"] or data["hasEditor"]:
    raise SystemExit("Old workbench/editor UI is still visible")
PY
}

assert_chart_hover() {
  local session="$1"
  local metrics_output
  metrics_output="$(session_eval "${session}" '() => {
    const rect = document.querySelector("[data-chart=\"generation\"] svg")?.getBoundingClientRect();
    return rect ? { x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2) } : null;
  }')"
  eval "$(RESULT_TEXT="${metrics_output}" python3 - <<'PY'
import json
import os
import re

text = os.environ["RESULT_TEXT"]
match = re.search(r'### Result\s*(.*?)\s*### Ran', text, re.S)
if not match:
    raise SystemExit("Missing Playwright eval result for chart hover metrics")
data = json.loads(match.group(1))
if not data:
    raise SystemExit("Missing chart SVG for hover assertion")
print(f"hover_x={int(data['x'])}")
print(f"hover_y={int(data['y'])}")
PY
)"
  "${PWCLI[@]}" --session "${session}" mousemove "${hover_x}" "${hover_y}" >/dev/null
  local tooltip_output
  tooltip_output="$(session_eval "${session}" '() => ({
    visible: Boolean(document.querySelector(".chart-tooltip")),
    text: document.querySelector(".chart-tooltip")?.textContent || ""
  })')"
  RESULT_TEXT="${tooltip_output}" python3 - <<'PY'
import json
import os
import re

text = os.environ["RESULT_TEXT"]
match = re.search(r'### Result\s*(.*?)\s*### Ran', text, re.S)
if not match:
    raise SystemExit("Missing Playwright eval result for chart hover tooltip")
data = json.loads(match.group(1))
if not data.get("visible"):
    raise SystemExit("Expected Recharts tooltip to appear on hover")
for label in ("Solar", "Grid import", "Battery discharge"):
    if label not in data.get("text", ""):
        raise SystemExit(f"Tooltip missing {label}: {data.get('text')!r}")
PY
}

assert_date_picker() {
  local session="$1"
  session_eval "${session}" '() => document.querySelector("button.date-trigger")?.click()' >/dev/null
  local output
  output="$(session_eval "${session}" '() => ({
    open: Boolean(document.querySelector(".calendar-popover")),
    shortcuts: Array.from(document.querySelectorAll(".shortcut-row button")).map((button) => button.textContent.trim()),
    hasGrid: document.querySelectorAll(".calendar-day-button").length >= 35
  })')"
  RESULT_TEXT="${output}" python3 - <<'PY'
import json
import os
import re

text = os.environ["RESULT_TEXT"]
match = re.search(r'### Result\s*(.*?)\s*### Ran', text, re.S)
if not match:
    raise SystemExit("Missing Playwright eval result for date picker")
data = json.loads(match.group(1))
if not data.get("open"):
    raise SystemExit("Expected calendar popover to open")
if data.get("shortcuts") != ["Yesterday", "Today", "Tomorrow"]:
    raise SystemExit(f"Unexpected date shortcuts: {data.get('shortcuts')!r}")
if not data.get("hasGrid"):
    raise SystemExit("Expected calendar grid to render")
PY
}

"${PWCLI[@]}" --session energy-ui-desktop open --config "${desktop_config}" "${URL}" >/dev/null
assert_dashboard energy-ui-desktop
assert_date_picker energy-ui-desktop
assert_chart_hover energy-ui-desktop
capture_screenshot energy-ui-desktop "${OUT_DIR}/dashboard-desktop.png"

"${PWCLI[@]}" --session energy-ui-mobile open --config "${mobile_config}" "${URL}" >/dev/null
assert_dashboard energy-ui-mobile
capture_screenshot energy-ui-mobile "${OUT_DIR}/dashboard-mobile.png"

echo "Energy UI browser check passed"
