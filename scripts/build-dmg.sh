#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${ROOT_DIR}/NaiveClient"
SCHEME="NaiveClient"
CONFIGURATION="${1:-Release}"
ARCH="${2:-$(uname -m)}"
VERSION="${3:-1.0.0}"

BUILD_DIR="${ROOT_DIR}/build"
APP_PATH="${BUILD_DIR}/${CONFIGURATION}/NaiveClient.app"
DIST_DIR="${ROOT_DIR}/dist"
DMG_NAME="NaiveClient-${VERSION}-macOS-${ARCH}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

echo "==> Download naive core"
bash "${ROOT_DIR}/scripts/download-naive.sh" "${ARCH}"

echo "==> Build ${SCHEME} (${CONFIGURATION})"
xcodebuild \
  -project "${PROJECT_DIR}/NaiveClient.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  SYMROOT="${BUILD_DIR}" \
  clean build

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Built app not found at ${APP_PATH}" >&2
  exit 1
fi

echo "==> Ad-hoc sign app and bundled naive binary"
/usr/bin/codesign --force --deep --sign - "${APP_PATH}/Contents/Resources/naive"
/usr/bin/codesign --force --deep --sign - "${APP_PATH}"

echo "==> Create DMG"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}" "${DIST_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "NaiveClient" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "Created ${DMG_PATH}"
