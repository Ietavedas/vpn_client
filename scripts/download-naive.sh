#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="${ROOT_DIR}/NaiveClient/NaiveClient/Resources"
ARCH="${1:-$(uname -m)}"

if [[ -z "${NAIVE_VERSION:-}" ]]; then
  NAIVE_VERSION="$(curl -fsSL "https://api.github.com/repos/klzgrad/naiveproxy/releases/latest" | python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'])")"
fi

mkdir -p "${RESOURCES_DIR}"

case "${ARCH}" in
  arm64|aarch64)
    ASSET_NAME="naive-macos-arm64"
    ;;
  x86_64|amd64)
    ASSET_NAME="naive-macos-x64"
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Downloading ${ASSET_NAME} from naiveproxy ${NAIVE_VERSION}..."
curl -fsSL \
  "https://github.com/klzgrad/naiveproxy/releases/download/${NAIVE_VERSION}/${ASSET_NAME}.tar.xz" \
  -o "${TMP_DIR}/naive.tar.xz"

tar -xJf "${TMP_DIR}/naive.tar.xz" -C "${TMP_DIR}"

NAIVE_BIN="$(find "${TMP_DIR}" -type f -name naive -print -quit)"
if [[ -z "${NAIVE_BIN}" ]]; then
  echo "naive binary not found in archive" >&2
  exit 1
fi

install -m 755 "${NAIVE_BIN}" "${RESOURCES_DIR}/naive"
echo "Installed naive to ${RESOURCES_DIR}/naive"
