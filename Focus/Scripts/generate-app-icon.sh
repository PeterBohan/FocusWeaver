#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="${ROOT_DIR}/Sources/FocusWeaverMac/Resources/AppIconSource.png"
OUTPUT_ICNS="${ROOT_DIR}/Sources/FocusWeaverMac/Resources/AppIcon.icns"
TEMP_DIR="$(mktemp -d /tmp/focusweaver.XXXXXX)"
ICONSET_DIR="${TEMP_DIR}/AppIcon.iconset"

if [[ ! -f "${SOURCE_ICON}" ]]; then
  echo "Missing source icon: ${SOURCE_ICON}"
  exit 1
fi

mkdir -p "${ICONSET_DIR}"

sips -z 16 16     "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32     "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64     "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256   "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512   "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "${SOURCE_ICON}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"
rm -rf "${TEMP_DIR}"

echo "Generated ${OUTPUT_ICNS}"
