#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${HOME}/Applications/CodexTouchBarHelper.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/CodexTouchBarHelper"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT="${LAUNCH_AGENT_DIR}/com.local.codex-touchbar-helper.plist"
CACHE_DIR="${HOME}/.codex/touchbar-usage"

"${PLUGIN_DIR}/scripts/build_touchbar_helper.sh"

mkdir -p "${CACHE_DIR}" "${LAUNCH_AGENT_DIR}"

for log_file in "${CACHE_DIR}/helper.out.log" "${CACHE_DIR}/helper.err.log"; do
  if [[ -f "${log_file}" ]] && [[ $(stat -f%z "${log_file}") -gt 2097152 ]]; then
    mv "${log_file}" "${log_file}.old"
  fi
done

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
    <string>Codex,ChatGPT,com.openai.codex</string>
  </dict>
</dict>
</plist>
PLIST

/usr/bin/pkill -fx "${EXECUTABLE}" >/dev/null 2>&1 || true
/bin/launchctl bootstrap "gui/$(id -u)" "${LAUNCH_AGENT}" >/dev/null 2>&1 || true
/bin/launchctl enable "gui/$(id -u)/com.local.codex-touchbar-helper" >/dev/null 2>&1 || true
/bin/launchctl kickstart -k "gui/$(id -u)/com.local.codex-touchbar-helper" >/dev/null 2>&1 || true

if ! /usr/bin/pgrep -fx "${EXECUTABLE}" >/dev/null 2>&1; then
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
