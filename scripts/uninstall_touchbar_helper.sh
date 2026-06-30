#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${HOME}/Applications/CodexTouchBarHelper.app"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/com.local.codex-touchbar-helper.plist"

if [[ -f "${LAUNCH_AGENT}" ]]; then
  /bin/launchctl bootout "gui/$(id -u)" "${LAUNCH_AGENT}" >/dev/null 2>&1 || true
  rm -f "${LAUNCH_AGENT}"
  echo "Removed ${LAUNCH_AGENT}"
fi

/usr/bin/pkill -x CodexTouchBarHelper >/dev/null 2>&1 || true

if [[ -d "${APP_DIR}" ]]; then
  rm -rf "${APP_DIR}"
  echo "Removed ${APP_DIR}"
fi

echo "CodexTouchBarHelper uninstalled. MTMR backups, if any, remain in ~/.codex/touchbar-usage/."
