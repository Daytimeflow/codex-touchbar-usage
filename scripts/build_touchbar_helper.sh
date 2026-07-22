#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_DIR="${PLUGIN_DIR}/helper/CodexTouchBarHelper"
APP_DIR="${APP_DIR:-${HOME}/Applications/CodexTouchBarHelper.app}"
CONFIGURATION="${CONFIGURATION:-release}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/codex-touchbar-clang-cache}"
export CLANG_MODULE_CACHE_PATH MACOSX_DEPLOYMENT_TARGET

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift is required. Install Xcode Command Line Tools, then rerun this script." >&2
  exit 3
fi

if /usr/bin/xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1 \
  && swift build -c "${CONFIGURATION}" --package-path "${PACKAGE_DIR}"; then
  BIN_DIR="$(swift build -c "${CONFIGURATION}" --package-path "${PACKAGE_DIR}" --show-bin-path)"
  BINARY="${BIN_DIR}/CodexTouchBarHelper"
else
  echo "SwiftPM is unavailable in this toolchain; falling back to direct swiftc build." >&2
  DIRECT_BUILD_DIR="${PACKAGE_DIR}/.build/direct-${CONFIGURATION}"
  TARGET_TRIPLE="$(uname -m)-apple-macosx${MACOSX_DEPLOYMENT_TARGET}"
  rm -rf "${DIRECT_BUILD_DIR}"
  mkdir -p "${DIRECT_BUILD_DIR}"

  swiftc \
    -target "${TARGET_TRIPLE}" \
    -parse-as-library \
    -emit-library \
    -static \
    -emit-module \
    -module-name CodexTouchBarCore \
    "${PACKAGE_DIR}"/Sources/CodexTouchBarCore/*.swift \
    -emit-module-path "${DIRECT_BUILD_DIR}/CodexTouchBarCore.swiftmodule" \
    -o "${DIRECT_BUILD_DIR}/libCodexTouchBarCore.a"

  swiftc \
    -target "${TARGET_TRIPLE}" \
    -I "${DIRECT_BUILD_DIR}" \
    -L "${DIRECT_BUILD_DIR}" \
    -lCodexTouchBarCore \
    "${PACKAGE_DIR}"/Sources/CodexTouchBarHelper/*.swift \
    -o "${DIRECT_BUILD_DIR}/CodexTouchBarHelper"

  BINARY="${DIRECT_BUILD_DIR}/CodexTouchBarHelper"
fi

if [[ ! -x "${BINARY}" ]]; then
  echo "Missing built helper binary: ${BINARY}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BINARY}" "${APP_DIR}/Contents/MacOS/CodexTouchBarHelper"
cp "${PACKAGE_DIR}/AppBundle/Info.plist" "${APP_DIR}/Contents/Info.plist"
chmod +x "${APP_DIR}/Contents/MacOS/CodexTouchBarHelper"

echo "Built ${APP_DIR}"
