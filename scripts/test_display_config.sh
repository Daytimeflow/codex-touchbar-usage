#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="${ROOT}/helper/CodexTouchBarHelper"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/codex-display-test.XXXXXX")"
trap 'rm -rf "${BUILD}"' EXIT
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/codex-touchbar-clang-cache"
swiftc -target "$(uname -m)-apple-macosx12.0" -DDISPLAY_STANDALONE \
  "${PACKAGE}/Sources/CodexTouchBarCore/Models.swift" \
  "${PACKAGE}/Sources/CodexTouchBarCore/Formatting.swift" \
  "${PACKAGE}/Sources/CodexTouchBarCore/DisplayConfiguration.swift" \
  "${PACKAGE}/Tests/CodexTouchBarCoreTests/DisplayConfigurationTests.swift" \
  -o "${BUILD}/test-display"
"${BUILD}/test-display"
