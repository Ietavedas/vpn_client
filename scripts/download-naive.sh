#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="${ROOT_DIR}/NaiveClient/NaiveClient/Resources"
ARCH="${1:-$(uname -m)}"

mkdir -p "${RESOURCES_DIR}"

RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/klzgrad/naiveproxy/releases/latest")"
NAIVE_VERSION="$(python3 -c "import json, sys; print(json.load(sys.stdin)['tag_name'])" <<< "${RELEASE_JSON}")"

case "${ARCH}" in
  arm64|aarch64)
    ASSET_PATTERN='-mac-arm64'
    ;;
  x86_64|amd64)
    ASSET_PATTERN='-mac-x64'
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

ASSET_NAME="$(ASSET_PATTERN="${ASSET_PATTERN}" python3 -c "
import json
import os
import sys

pattern = os.environ['ASSET_PATTERN']
release = json.loads(sys.argv[1])

for asset in release.get('assets', []):
    name = asset['name']
    if name.endswith('.tar.xz') and pattern in name and 'openwrt' not in name:
        print(name)
        break
else:
    raise SystemExit(f'No matching naiveproxy macOS asset found for pattern {pattern}')
" "${RELEASE_JSON}")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading ${ASSET_NAME} from naiveproxy ${NAIVE_VERSION}..."
curl -fsSL \
  "https://github.com/klzgrad/naiveproxy/releases/download/${NAIVE_VERSION}/${ASSET_NAME}" \
  -o "${TMP_DIR}/naive.tar.xz"

tar -xJf "${TMP_DIR}/naive.tar.xz" -C "${TMP_DIR}"

NAIVE_BIN="$(find "${TMP_DIR}" -type f \( -name naive -o -name naiveproxy \) -print -quit)"
if [[ -z "${NAIVE_BIN}" ]]; then
  echo "naive binary not found in archive ${ASSET_NAME}" >&2
  exit 1
fi

install -m 755 "${NAIVE_BIN}" "${RESOURCES_DIR}/naive"
echo "Installed naive to ${RESOURCES_DIR}/naive"
