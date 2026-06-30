#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${HOME}/Applications/CodexTouchBarHelper.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/CodexTouchBarHelper"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/com.local.codex-touchbar-helper.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install_touchbar_helper.sh"
LABEL="com.local.codex-touchbar-helper"
DOMAIN="gui/$(id -u)"
SERVICE="${DOMAIN}/${LABEL}"

if [[ ! -x "${EXECUTABLE}" ]]; then
  cat >&2 <<MSG
CodexTouchBarHelper is not installed at:
  ${EXECUTABLE}

Install it first:
  ${INSTALL_SCRIPT}
MSG
  exit 1
fi

if [[ -f "${LAUNCH_AGENT}" ]]; then
  /bin/launchctl enable "${SERVICE}" >/dev/null 2>&1 || true
  if /bin/launchctl print "${SERVICE}" >/dev/null 2>&1; then
    /bin/launchctl kickstart -k "${SERVICE}" >/dev/null 2>&1 || true
  else
    /bin/launchctl bootstrap "${DOMAIN}" "${LAUNCH_AGENT}" >/dev/null 2>&1 || true
    /bin/launchctl kickstart -k "${SERVICE}" >/dev/null 2>&1 || true
  fi
fi

if ! /usr/bin/pgrep -x CodexTouchBarHelper >/dev/null 2>&1; then
  /usr/bin/open -gja "${APP_DIR}" >/dev/null 2>&1 || "${EXECUTABLE}" >/dev/null 2>&1 &
fi

echo "CodexTouchBarHelper start requested."
echo "Make Codex frontmost to show the Touch Bar view."
