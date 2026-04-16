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

open_page() {
  local session="$1"
  local config="$2"
  local url="$3"
  "${PWCLI[@]}" --session "${session}" open --config "${config}" "${url}" >/dev/null
}

first_calendar_ref() {
  local session="$1"
  local snapshot
  snapshot="$("${PWCLI[@]}" --session "${session}" snapshot)"
  SNAPSHOT_TEXT="${snapshot}" python3 - <<'PY'
import os
import re

text = os.environ["SNAPSHOT_TEXT"]
match = re.search(r'button .*?\[ref=(e\d+)\]', text, re.S)
if not match:
    raise SystemExit("Could not find a calendar day button in snapshot")
print(match.group(1))
PY
}

capture_group() {
  local session="$1"
  local config="$2"
  local suffix="$3"

  open_page "${session}" "${config}" "${URL}"
  capture_screenshot "${session}" "${OUT_DIR}/overview-${suffix}.png"

  open_page "${session}" "${config}" "${URL%/}/timeline"
  capture_screenshot "${session}" "${OUT_DIR}/timeline-${suffix}.png"

  open_page "${session}" "${config}" "${URL%/}/tesla"
  capture_screenshot "${session}" "${OUT_DIR}/tesla-${suffix}.png"

  local ref
  ref="$(first_calendar_ref "${session}")"
  "${PWCLI[@]}" --session "${session}" click "${ref}" >/dev/null
  capture_screenshot "${session}" "${OUT_DIR}/tesla-modal-${suffix}.png"
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
    "${OUT_DIR}/overview-mobile.png",
    "${OUT_DIR}/timeline-mobile.png",
    "${OUT_DIR}/tesla-mobile.png",
    "${OUT_DIR}/tesla-modal-mobile.png"
  ]
}
EOF
