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

assert_dashboard() {
  local session="$1"
  local output
  output="$("${PWCLI[@]}" --session "${session}" eval '() => ({
    title: document.querySelector("h1")?.textContent || "",
    hasDate: Boolean(document.querySelector("input[type=date]")),
    hasChart: Boolean(document.querySelector("svg.chart")),
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
for key in ("hasDate", "hasChart", "hasHistory"):
    if not data[key]:
        raise SystemExit(f"Dashboard assertion failed: {key}")
if data["hasWorkbench"] or data["hasEditor"]:
    raise SystemExit("Old workbench/editor UI is still visible")
PY
}

"${PWCLI[@]}" --session energy-ui-desktop open --config "${desktop_config}" "${URL}" >/dev/null
assert_dashboard energy-ui-desktop
capture_screenshot energy-ui-desktop "${OUT_DIR}/dashboard-desktop.png"

"${PWCLI[@]}" --session energy-ui-mobile open --config "${mobile_config}" "${URL}" >/dev/null
assert_dashboard energy-ui-mobile
capture_screenshot energy-ui-mobile "${OUT_DIR}/dashboard-mobile.png"

echo "Energy UI browser check passed"
