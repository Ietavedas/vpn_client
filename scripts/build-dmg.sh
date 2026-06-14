#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${ROOT_DIR}/NaiveClient"
SCHEME="NaiveClient"
CONFIGURATION="${1:-Release}"
ARCH="${2:-$(uname -m)}"
VERSION="${3:-1.0.0}"

BUILD_DIR="${ROOT_DIR}/build"
DIST_DIR="${ROOT_DIR}/dist"
DMG_NAME="NaiveClient-${VERSION}-macOS-${ARCH}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

echo "==> Download naive core"
bash "${ROOT_DIR}/scripts/download-naive.sh" "${ARCH}"

echo "==> Build ${SCHEME} (${CONFIGURATION}) for ${ARCH}"
XCODE_ARGS=(
  -project "${PROJECT_DIR}/NaiveClient.xcodeproj"
  -scheme "${SCHEME}"
  -configuration "${CONFIGURATION}"
  -derivedDataPath "${BUILD_DIR}/DerivedData"
  CODE_SIGNING_ALLOWED=NO
)

if [[ "${ARCH}" == "x86_64" ]]; then
  XCODE_ARGS+=(ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO)
fi

xcodebuild "${XCODE_ARGS[@]}" clean build

APP_PATH="$(find "${BUILD_DIR}/DerivedData/Build/Products/${CONFIGURATION}" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Built app not found under ${BUILD_DIR}/DerivedData/Build/Products/${CONFIGURATION}" >&2
  exit 1
fi

echo "Built app: ${APP_PATH}"

echo "==> Ad-hoc sign app and bundled naive binary"
ENTITLEMENTS="${ROOT_DIR}/NaiveClient/NaiveClient/NaiveClient.entitlements"
/usr/bin/codesign --force --sign - --options runtime "${APP_PATH}/Contents/Resources/naive"
/usr/bin/codesign --force --sign - --options runtime --entitlements "${ENTITLEMENTS}" "${APP_PATH}"
/usr/bin/codesign --verify --verbose=2 "${APP_PATH}"

echo "==> Create DMG"
rm -rf "${STAGING_DIR}" "${DMG_PATH}"
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
