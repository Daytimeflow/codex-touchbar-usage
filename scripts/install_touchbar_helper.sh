#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${HOME}/Applications/CodexTouchBarHelper.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/CodexTouchBarHelper"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT="${LAUNCH_AGENT_DIR}/com.local.codex-touchbar-helper.plist"
CACHE_DIR="${HOME}/.codex/touchbar-usage"
MTMR_DIR="${HOME}/Library/Application Support/MTMR"
MTMR_APP="/Applications/MTMR.app"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
REMOVE_MTMR="${REMOVE_MTMR:-0}"

"${PLUGIN_DIR}/scripts/build_touchbar_helper.sh"

mkdir -p "${CACHE_DIR}" "${LAUNCH_AGENT_DIR}"

if [[ -d "${MTMR_DIR}" || -d "${MTMR_APP}" ]]; then
  if [[ "${REMOVE_MTMR}" == "1" ]]; then
    BACKUP_DIR="${CACHE_DIR}/mtmr-backup-${TIMESTAMP}"
    mkdir -p "${BACKUP_DIR}"
    if [[ -d "${MTMR_DIR}" ]]; then
      cp -R "${MTMR_DIR}" "${BACKUP_DIR}/MTMR-config"
    fi
    if [[ -d "${MTMR_APP}" ]]; then
      echo "${MTMR_APP}" > "${BACKUP_DIR}/removed-app-path.txt"
    fi
    echo "Backed up MTMR state to ${BACKUP_DIR}"
  else
    cat <<MSG
Detected MTMR. CodexTouchBarHelper does not require MTMR.
Leaving MTMR installed. To back up and remove MTMR during install, rerun:
  REMOVE_MTMR=1 ${BASH_SOURCE[0]}
MSG
  fi
fi

if [[ "${REMOVE_MTMR}" == "1" ]]; then
  /usr/bin/osascript -e 'tell application "MTMR" to quit' >/dev/null 2>&1 || true
  /usr/bin/pkill -x MTMR >/dev/null 2>&1 || true

  if [[ -d "${MTMR_APP}" ]]; then
    if rm -rf "${MTMR_APP}" 2>/dev/null; then
      echo "Removed ${MTMR_APP}"
    elif /usr/bin/sudo -n /bin/rm -rf "${MTMR_APP}" 2>/dev/null; then
      echo "Removed ${MTMR_APP} with administrator permission"
    else
      cat >&2 <<MSG
Could not remove ${MTMR_APP} without administrator permission.
The helper no longer uses MTMR, and MTMR has been quit. To finish removing the
app later, run:
  sudo rm -rf "${MTMR_APP}"
MSG
    fi
  fi

  if [[ -d "${MTMR_DIR}" ]]; then
    rm -rf "${MTMR_DIR}"
    echo "Removed ${MTMR_DIR}"
  fi

  rm -f \
    "${HOME}/Library/LaunchAgents/com.toxblh.mtmr.plist" \
    "${HOME}/Library/LaunchAgents/com.mtmr.MTMR.plist"
fi

if [[ -f "${LAUNCH_AGENT}" ]]; then
  /bin/launchctl bootout "gui/$(id -u)" "${LAUNCH_AGENT}" >/dev/null 2>&1 || true
fi

cat > "${LAUNCH_AGENT}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.local.codex-touchbar-helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>${EXECUTABLE}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${CACHE_DIR}/helper.out.log</string>
  <key>StandardErrorPath</key>
  <string>${CACHE_DIR}/helper.err.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CODEX_TOUCHBAR_TARGET_APPS</key>
    <string>Codex,com.openai.codex</string>
  </dict>
</dict>
</plist>
PLIST

/usr/bin/pkill -x CodexTouchBarHelper >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENT}" >/dev/null 2>&1 || true
/bin/launchctl enable "gui/$(id -u)/com.local.codex-touchbar-helper" >/dev/null 2>&1 || true
/bin/launchctl kickstart -k "gui/$(id -u)/com.local.codex-touchbar-helper" >/dev/null 2>&1 || true

if ! /usr/bin/pgrep -x CodexTouchBarHelper >/dev/null 2>&1; then
  /usr/bin/open -gja "${APP_DIR}" || true
fi

cat <<MSG
Installed CodexTouchBarHelper.

Open Codex and make it frontmost. The native helper only refreshes usage while
Codex is focused, and hides the Touch Bar view when you switch away.

Logs:
  ${CACHE_DIR}/helper.out.log
  ${CACHE_DIR}/helper.err.log
MSG
