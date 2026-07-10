#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_APP="${SCRIPT_DIR}/CodexTouchBarHelper.app"
APP_DIR="${HOME}/Applications/CodexTouchBarHelper.app"
EXECUTABLE="${APP_DIR}/Contents/MacOS/CodexTouchBarHelper"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
LAUNCH_AGENT="${LAUNCH_AGENT_DIR}/com.local.codex-touchbar-helper.plist"
CACHE_DIR="${HOME}/.codex/touchbar-usage"
DOMAIN="gui/$(id -u)"

wait_for_helper() {
  for _ in {1..30}; do
    if /usr/bin/pgrep -fx "${EXECUTABLE}" >/dev/null 2>&1; then
      return 0
    fi
    /bin/sleep 0.1
  done
  return 1
}

if [[ ! -x "${SOURCE_APP}/Contents/MacOS/CodexTouchBarHelper" ]]; then
  echo "CodexTouchBarHelper.app is missing from the release folder." >&2
  exit 1
fi

mkdir -p "${HOME}/Applications" "${LAUNCH_AGENT_DIR}" "${CACHE_DIR}"

for log_file in "${CACHE_DIR}/helper.out.log" "${CACHE_DIR}/helper.err.log"; do
  if [[ -f "${log_file}" ]] && [[ $(stat -f%z "${log_file}") -gt 2097152 ]]; then
    mv "${log_file}" "${log_file}.old"
  fi
done

if [[ -f "${LAUNCH_AGENT}" ]]; then
  /bin/launchctl bootout "${DOMAIN}" "${LAUNCH_AGENT}" >/dev/null 2>&1 || true
fi
/usr/bin/pkill -fx "${EXECUTABLE}" >/dev/null 2>&1 || true
rm -rf "${APP_DIR}"
/usr/bin/ditto "${SOURCE_APP}" "${APP_DIR}"

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

/bin/launchctl bootstrap "${DOMAIN}" "${LAUNCH_AGENT}" >/dev/null 2>&1 || true
/bin/launchctl enable "${DOMAIN}/com.local.codex-touchbar-helper" >/dev/null 2>&1 || true
/bin/launchctl kickstart -k "${DOMAIN}/com.local.codex-touchbar-helper" >/dev/null 2>&1 || true

if ! wait_for_helper; then
  echo "CodexTouchBarHelper was installed but LaunchAgent could not start it." >&2
  echo "Inspect with: launchctl print ${DOMAIN}/com.local.codex-touchbar-helper" >&2
  exit 2
fi

if [[ ! -s "${HOME}/.codex/auth.json" ]]; then
  echo "Warning: Codex CLI credentials are missing. Official quota data cannot refresh." >&2
  echo "Run: codex login --device-auth" >&2
fi

echo "Installed CodexTouchBarHelper to ${APP_DIR}"
echo "Focus Codex or ChatGPT to show the Touch Bar panel."
