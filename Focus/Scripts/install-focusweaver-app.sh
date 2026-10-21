#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="FocusWeaver.app"
APP_DIR="/Applications/${APP_NAME}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "$ROOT_DIR"
if [[ -x "${ROOT_DIR}/Scripts/generate-app-icon.sh" ]]; then
  "${ROOT_DIR}/Scripts/generate-app-icon.sh"
fi
swift build -c release

BIN_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/release/FocusWeaverMac" | head -n 1)"
if [[ -z "${BIN_PATH}" ]]; then
  echo "Could not find release binary for FocusWeaverMac."
  exit 1
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "${MACOS_DIR}/FocusWeaverMac"
chmod +x "${MACOS_DIR}/FocusWeaverMac"
cp "${ROOT_DIR}/Sources/FocusWeaverMac/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
if [[ -f "${ROOT_DIR}/Sources/FocusWeaverMac/Resources/AppIcon.icns" ]]; then
  cp "${ROOT_DIR}/Sources/FocusWeaverMac/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
touch "${APP_DIR}"

echo "Installed ${APP_DIR}"
