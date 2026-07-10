#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="${VERSION:-$(/usr/bin/plutil -extract version raw "${PLUGIN_DIR}/.codex-plugin/plugin.json")}"
ARCH="arm64"
DIST_DIR="${DIST_DIR:-${PLUGIN_DIR}/dist}"
PACKAGE_NAME="CodexTouchBarUsage-v${VERSION}-${ARCH}"
STAGE_DIR="${DIST_DIR}/stage/${PACKAGE_NAME}"
APP_DIR="${STAGE_DIR}/CodexTouchBarHelper.app"
ZIP_PATH="${DIST_DIR}/${PACKAGE_NAME}.zip"

rm -rf "${DIST_DIR}/stage"
mkdir -p "${STAGE_DIR}"

APP_DIR="${APP_DIR}" "${PLUGIN_DIR}/scripts/build_touchbar_helper.sh"
/usr/bin/codesign --force --deep --sign - "${APP_DIR}" >/dev/null

cp "${PLUGIN_DIR}/packaging/install_release.sh" "${STAGE_DIR}/install.sh"
cp "${PLUGIN_DIR}/scripts/uninstall_touchbar_helper.sh" "${STAGE_DIR}/uninstall.sh"
cp "${PLUGIN_DIR}/packaging/README.txt" "${STAGE_DIR}/README.txt"
chmod +x "${STAGE_DIR}/install.sh" "${STAGE_DIR}/uninstall.sh"

rm -f "${ZIP_PATH}" "${ZIP_PATH}.sha256"
/usr/bin/xattr -cr "${STAGE_DIR}"
(
  cd "${DIST_DIR}/stage"
  /usr/bin/zip -qry "${ZIP_PATH}" "${PACKAGE_NAME}"
)
(
  cd "${DIST_DIR}"
  /usr/bin/shasum -a 256 "$(basename "${ZIP_PATH}")" > "$(basename "${ZIP_PATH}").sha256"
)

echo "Created ${ZIP_PATH}"
echo "Created ${ZIP_PATH}.sha256"
