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

cat > "${desktop_config}" <<'EOF'
{
  "browser": {
    "launchOptions": { "headless": true },
    "contextOptions": { "viewport": { "width": 1440, "height": 1280 } }
  }
}
EOF

cat > "${mobile_config}" <<'EOF'
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

assert_workbench_series_editor() {
  local session="$1"
  local metrics_output
  metrics_output="$(session_eval "${session}" '() => {
    const clickTab = (label) => {
      const button = Array.from(document.querySelectorAll("#workbench-tabs [data-workbench-tab]"))
        .find((item) => item.textContent.trim() === label);
      if (button) button.click();
    };
    clickTab("Prices");
    const svg = document.querySelector("#workbench-panel .series-chart svg");
    const readSeries = () => Array.from(
      document.querySelectorAll("#workbench-panel [data-workbench-series-path=\"config.forecasts.prices.import_czk_per_kwh\"]")
    ).slice(0, 16).map((input) => Number(input.value));
    if (!svg) {
      return { path: window.location.pathname, error: "missing-series-chart" };
    }
    const rect = svg.getBoundingClientRect();
    const plotLeft = rect.left + rect.width * (64 / 1100);
    const plotTop = rect.top + rect.height * (24 / 240);
    const plotBottom = rect.top + rect.height * ((24 + 168) / 240);
    const firstBucketX = Math.round(plotLeft + 2);
    const dragEndX = Math.round(Math.min(rect.right - 12, plotLeft + rect.width * (260 / 1100)));
    const before = readSeries();
    const clickY = Math.round(before[0] > 1.5 ? plotBottom - 6 : plotTop + 6);
    const dragStartY = Math.round(before[0] > 1.5 ? plotBottom - 10 : plotTop + 10);
    const dragEndY = Math.round(before[0] > 1.5 ? plotTop + 10 : plotBottom - 10);
    return {
      path: window.location.pathname,
      before,
      firstBucketX,
      clickY,
      dragStartY,
      dragEndX,
      dragEndY,
    };
  }')"
  eval "$(RESULT_TEXT="${metrics_output}" python3 - <<'PY'
import json
import os
import re

text = os.environ["RESULT_TEXT"]
match = re.search(r'### Result\s*(.*?)\s*### Ran', text, re.S)
if not match:
    raise SystemExit("Missing Playwright eval result for workbench series editor metrics")
data = json.loads(match.group(1))
if data.get("path") != "/workbench":
    raise SystemExit(f"Workbench series editor left the route: {data.get('path')}")
if data.get("error"):
    raise SystemExit(f"Workbench series editor assertion failed: {data['error']}")
for key in ("firstBucketX", "clickY", "dragStartY", "dragEndX", "dragEndY"):
    print(f"{key}={int(round(float(data[key])))}")
PY
)"

  "${PWCLI[@]}" --session "${session}" mousemove "${firstBucketX}" "${clickY}" >/dev/null
  "${PWCLI[@]}" --session "${session}" mousedown >/dev/null
  "${PWCLI[@]}" --session "${session}" mouseup >/dev/null

  local after_click_output
  after_click_output="$(session_eval "${session}" '() => ({
    path: window.location.pathname,
    values: Array.from(
      document.querySelectorAll("#workbench-panel [data-workbench-series-path=\"config.forecasts.prices.import_czk_per_kwh\"]")
    ).slice(0, 16).map((input) => Number(input.value))
  })')"

  "${PWCLI[@]}" --session "${session}" mousemove "${firstBucketX}" "${dragStartY}" >/dev/null
  "${PWCLI[@]}" --session "${session}" mousedown >/dev/null
  "${PWCLI[@]}" --session "${session}" mousemove "$(( firstBucketX + (dragEndX - firstBucketX) / 3 ))" "$(( dragStartY + (dragEndY - dragStartY) / 3 ))" >/dev/null
  "${PWCLI[@]}" --session "${session}" mousemove "$(( firstBucketX + (dragEndX - firstBucketX) * 2 / 3 ))" "$(( dragStartY + (dragEndY - dragStartY) * 2 / 3 ))" >/dev/null
  "${PWCLI[@]}" --session "${session}" mousemove "${dragEndX}" "${dragEndY}" >/dev/null
  "${PWCLI[@]}" --session "${session}" mouseup >/dev/null

  local after_drag_output
  after_drag_output="$(session_eval "${session}" '() => ({
    path: window.location.pathname,
    values: Array.from(
      document.querySelectorAll("#workbench-panel [data-workbench-series-path=\"config.forecasts.prices.import_czk_per_kwh\"]")
    ).slice(0, 16).map((input) => Number(input.value)),
    selection: String(window.getSelection())
  })')"

  BEFORE_OUTPUT="${metrics_output}" AFTER_CLICK_OUTPUT="${after_click_output}" AFTER_DRAG_OUTPUT="${after_drag_output}" python3 - <<'PY'
import json
import os
import re

def parse_result(name: str):
    text = os.environ[name]
    match = re.search(r'### Result\s*(.*?)\s*### Ran', text, re.S)
    if not match:
        raise SystemExit(f"Missing Playwright eval result for {name}")
    return json.loads(match.group(1))

before = parse_result("BEFORE_OUTPUT")
after_click = parse_result("AFTER_CLICK_OUTPUT")
after_drag = parse_result("AFTER_DRAG_OUTPUT")

if after_click.get("path") != "/workbench":
    raise SystemExit(f"Workbench series editor left the route after click: {after_click.get('path')}")
if after_drag.get("path") != "/workbench":
    raise SystemExit(f"Workbench series editor left the route after drag: {after_drag.get('path')}")

before_values = before.get("before") or []
after_click_values = after_click.get("values") or []
after_drag_values = after_drag.get("values") or []

click_changed = [index for index, (old, new) in enumerate(zip(before_values, after_click_values)) if abs(old - new) > 0.001]
drag_changed = [index for index, (old, new) in enumerate(zip(after_click_values, after_drag_values)) if abs(old - new) > 0.001]

if not click_changed or click_changed[0] != 0:
    raise SystemExit(f"Expected the first bucket to change on a real click, got {click_changed}")
if len(drag_changed) < 4:
    raise SystemExit(f"Expected real dragging to update several buckets, got {drag_changed}")
if after_drag.get("selection"):
    raise SystemExit(f"Dragging should not leave selected text, got {after_drag.get('selection')!r}")
PY
}

assert_session_path() {
  local session="$1"
  local expected="$2"
  local output
  output="$(session_eval "${session}" '() => window.location.pathname')"
  local actual
  actual="$(RESULT_TEXT="${output}" python3 - <<'PY'
import os
import re

text = os.environ["RESULT_TEXT"]
match = re.search(r'### Result\s+"([^"]+)"', text, re.S)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected route for session ${session}: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
}

open_page() {
  local session="$1"
  local config="$2"
  local url="$3"
  "${PWCLI[@]}" --session "${session}" open --config "${config}" "${url}" >/dev/null
}

route_url() {
  local route="$1"
  BASE_URL="${URL}" TARGET_ROUTE="${route}" python3 - <<'PY'
import os
from urllib.parse import urlparse, urlunparse

raw = os.environ["BASE_URL"]
route = os.environ["TARGET_ROUTE"]
parsed = urlparse(raw)
if route == "/":
    path = parsed.path or "/"
else:
    path = route
print(urlunparse((parsed.scheme, parsed.netloc, path, "", parsed.query, "")))
PY
}

calendar_modal_ref() {
  local session="$1"
  local snapshot
  snapshot="$("${PWCLI[@]}" --session "${session}" snapshot)"
  SNAPSHOT_TEXT="${snapshot}" python3 - <<'PY'
import os
import re

text = os.environ["SNAPSHOT_TEXT"]
if "Tesla day edits are disabled" in text:
    print("")
    raise SystemExit(0)
match = re.search(r'button .*?\[ref=(e\d+)\]', text, re.S)
if match:
    print(match.group(1))
    raise SystemExit(0)
print("")
PY
}

capture_group() {
  local session="$1"
  local config="$2"
  local suffix="$3"

  local overview_url
  local timeline_url
  local tesla_url
  local workbench_url
  overview_url="$(route_url "/")"
  timeline_url="$(route_url "/timeline")"
  tesla_url="$(route_url "/tesla")"
  workbench_url="$(route_url "/workbench")"

  open_page "${session}" "${config}" "${overview_url}"
  capture_screenshot "${session}" "${OUT_DIR}/overview-${suffix}.png"

  open_page "${session}" "${config}" "${timeline_url}"
  capture_screenshot "${session}" "${OUT_DIR}/timeline-${suffix}.png"

  open_page "${session}" "${config}" "${tesla_url}"
  capture_screenshot "${session}" "${OUT_DIR}/tesla-${suffix}.png"

  open_page "${session}" "${config}" "${workbench_url}"
  local workbench_snapshot
  workbench_snapshot="$("${PWCLI[@]}" --session "${session}" snapshot)"
  local prices_ref
  prices_ref="$(SNAPSHOT_TEXT="${workbench_snapshot}" python3 - <<'PY'
import os
import re

text = os.environ["SNAPSHOT_TEXT"]
match = re.search(r'button "Prices" \[ref=(e\d+)\]', text)
print(match.group(1) if match else "")
PY
)"
  if [[ -z "${prices_ref}" ]]; then
    echo "Failed to locate workbench Prices tab ref for ${session}" >&2
    exit 1
  fi
  "${PWCLI[@]}" --session "${session}" click "${prices_ref}" >/dev/null
  assert_session_path "${session}" "/workbench"
  workbench_snapshot="$("${PWCLI[@]}" --session "${session}" snapshot)"
  local results_ref
  results_ref="$(SNAPSHOT_TEXT="${workbench_snapshot}" python3 - <<'PY'
import os
import re

text = os.environ["SNAPSHOT_TEXT"]
match = re.search(r'button "Results" \[ref=(e\d+)\]', text)
print(match.group(1) if match else "")
PY
)"
  if [[ -z "${results_ref}" ]]; then
    echo "Failed to locate workbench Results tab ref for ${session}" >&2
    exit 1
  fi
  "${PWCLI[@]}" --session "${session}" click "${results_ref}" >/dev/null
  assert_session_path "${session}" "/workbench"
  assert_workbench_series_editor "${session}"
  open_page "${session}" "${config}" "${workbench_url}"
  capture_screenshot "${session}" "${OUT_DIR}/workbench-${suffix}.png"

  local ref
  ref="$(calendar_modal_ref "${session}")"
  if [[ -n "${ref}" ]]; then
    "${PWCLI[@]}" --session "${session}" click "${ref}" >/dev/null
    capture_screenshot "${session}" "${OUT_DIR}/tesla-modal-${suffix}.png"
  else
    cp "${OUT_DIR}/tesla-${suffix}.png" "${OUT_DIR}/tesla-modal-${suffix}.png"
  fi
}

capture_group "energy-ui-desktop" "${desktop_config}" "desktop"
capture_group "energy-ui-mobile" "${mobile_config}" "mobile"

cat <<EOF
{
  "outDir": "${OUT_DIR}",
  "artifacts": [
    "${OUT_DIR}/overview-desktop.png",
    "${OUT_DIR}/timeline-desktop.png",
    "${OUT_DIR}/tesla-desktop.png",
    "${OUT_DIR}/tesla-modal-desktop.png",
    "${OUT_DIR}/workbench-desktop.png",
    "${OUT_DIR}/overview-mobile.png",
    "${OUT_DIR}/timeline-mobile.png",
    "${OUT_DIR}/tesla-mobile.png",
    "${OUT_DIR}/tesla-modal-mobile.png",
    "${OUT_DIR}/workbench-mobile.png"
  ]
}
EOF
