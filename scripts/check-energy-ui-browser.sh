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
