#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="${ROOT_DIR}/NaiveClient/NaiveClient/Resources"
ARCH="${1:-$(uname -m)}"

mkdir -p "${RESOURCES_DIR}"

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

curl_github() {
  local url="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    if curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "User-Agent: NaiveClient-CI" \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
      "${url}"; then
      return 0
    fi
    echo "GitHub request failed (attempt ${attempt}/5), retrying..." >&2
    sleep "${attempt}"
  done
  return 1
}

curl_download() {
  local url="$1"
  local output="$2"
  local attempt
  for attempt in 1 2 3 4 5; do
    if curl -fsSL -L \
      -H "User-Agent: NaiveClient-CI" \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
      "${url}" \
      -o "${output}"; then
      return 0
    fi
    echo "Download failed (attempt ${attempt}/5), retrying..." >&2
    sleep "${attempt}"
  done
  return 1
}

RELEASE_JSON="$(curl_github "https://api.github.com/repos/klzgrad/naiveproxy/releases/latest")"

mapfile -t ASSET_META < <(ASSET_PATTERN="${ASSET_PATTERN}" python3 -c "
import json
import os
import sys

pattern = os.environ['ASSET_PATTERN']
release = json.loads(sys.argv[1])

for asset in release.get('assets', []):
    name = asset['name']
    if name.endswith('.tar.xz') and pattern in name and 'openwrt' not in name:
        print(release['tag_name'])
        print(name)
        print(asset['browser_download_url'])
        break
else:
    raise SystemExit(f'No matching naiveproxy macOS asset found for pattern {pattern}')
" "${RELEASE_JSON}")

NAIVE_VERSION="${ASSET_META[0]}"
ASSET_NAME="${ASSET_META[1]}"
DOWNLOAD_URL="${ASSET_META[2]}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading ${ASSET_NAME} from naiveproxy ${NAIVE_VERSION}..."
curl_download "${DOWNLOAD_URL}" "${TMP_DIR}/naive.tar.xz"

tar -xJf "${TMP_DIR}/naive.tar.xz" -C "${TMP_DIR}"

NAIVE_BIN="$(find "${TMP_DIR}" -type f \( -name naive -o -name naiveproxy \) -print -quit)"
if [[ -z "${NAIVE_BIN}" ]]; then
  echo "naive binary not found in archive ${ASSET_NAME}" >&2
  exit 1
fi

install -m 755 "${NAIVE_BIN}" "${RESOURCES_DIR}/naive"
echo "Installed naive to ${RESOURCES_DIR}/naive"
