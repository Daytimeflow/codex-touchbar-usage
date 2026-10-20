#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${ROOT}/helper/CodexTouchBarHelper"
BUILD="$(mktemp -d /tmp/touchbar-ui-test.XXXXXX)"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-touchbar-clang-cache"
TARGET="$(uname -m)-apple-macosx12.0"
swiftc -target "${TARGET}" -parse-as-library -emit-library -static -emit-module \
  -module-name CodexTouchBarCore \
  "${PACKAGE}/Sources/CodexTouchBarCore/Models.swift" \
  "${PACKAGE}/Sources/CodexTouchBarCore/Formatting.swift" \
  "${PACKAGE}/Sources/CodexTouchBarCore/DisplayConfiguration.swift" \
  "${PACKAGE}/Sources/CodexTouchBarCore/ZCodeModels.swift" \
  -emit-module-path "${BUILD}/CodexTouchBarCore.swiftmodule" -o "${BUILD}/libCodexTouchBarCore.a"
swiftc -target "${TARGET}" -I "${BUILD}" -L "${BUILD}" -lCodexTouchBarCore \
  "${PACKAGE}/Sources/CodexTouchBarHelper/FrontmostAppMonitor.swift" \
  "${PACKAGE}/Sources/CodexTouchBarHelper/TouchBarController.swift" \
  "${PACKAGE}/Sources/CodexTouchBarHelper/UsageTouchBarView.swift" \
  "${PACKAGE}/Sources/CodexTouchBarHelper/ZCodeTouchBarView.swift" \
  "${PACKAGE}/Tests/TouchBarUIHarness.swift" -o "${BUILD}/test-ui"
"${BUILD}/test-ui" "${1:-/tmp/codex-touchbar-preview}"
