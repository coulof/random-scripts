#!/usr/bin/env bash
# Extract kernel version from a Harvester release without deploying a node.
# Downloads the rootfs squashfs, extracts only /lib/modules, reads dir name.
#
# Usage: ./get-harvester-kernel.sh <version> [arch]
#   version e.g. v1.8.1-rc2, v1.7.1
#   arch    amd64 (default) | arm64
#
# Requires: curl, unsquashfs (squashfs-tools)

set -euo pipefail

VERSION="${1:?Usage: $0 <version> [amd64|arm64]}"
ARCH="${2:-amd64}"
BASE_URL="https://releases.rancher.com/harvester/${VERSION}"
SQUASHFS="harvester-${VERSION}-rootfs-${ARCH}.squashfs"
URL="${BASE_URL}/${SQUASHFS}"
SHA_URL="${BASE_URL}/harvester-${VERSION}-${ARCH}.sha512"

command -v unsquashfs >/dev/null 2>&1 || {
  echo "[ERROR] unsquashfs not found. Install squashfs-tools (apt install squashfs-tools)." >&2
  exit 1
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "[INFO] Fetching ${URL}"
curl -fSL --progress-bar -o "${WORKDIR}/${SQUASHFS}" "${URL}"

# Optional checksum verification. sha512 file lists multiple assets;
# grep the line matching our squashfs filename.
echo "[INFO] Verifying checksum"
if curl -fsSL -o "${WORKDIR}/checksums.sha512" "${SHA_URL}"; then
  EXPECTED="$(grep "${SQUASHFS}" "${WORKDIR}/checksums.sha512" | awk '{print $1}' || true)"
  if [ -n "${EXPECTED}" ]; then
    ACTUAL="$(sha512sum "${WORKDIR}/${SQUASHFS}" | awk '{print $1}')"
    if [ "${EXPECTED}" != "${ACTUAL}" ]; then
      echo "[ERROR] Checksum mismatch. Expected ${EXPECTED}, got ${ACTUAL}" >&2
      exit 1
    fi
    echo "[INFO] Checksum OK"
  else
    echo "[WARN] Could not find ${SQUASHFS} entry in sha512 file, skipping verification" >&2
  fi
else
  echo "[WARN] Could not fetch sha512 file, skipping verification" >&2
fi

echo "[INFO] Locating lib/modules path inside squashfs (usr-merge means it may be usr/lib/modules)"
MOD_PATH="$(unsquashfs -l "${WORKDIR}/${SQUASHFS}" \
  | grep -oE '[^[:space:]]*lib/modules/[^/[:space:]]+' \
  | sed -e 's#^/##' -e 's#^squashfs-root/##' \
  | sort -u | head -1)"

if [ -z "${MOD_PATH}" ]; then
  echo "[ERROR] Could not find any */lib/modules/* path in squashfs listing — layout differs for this release, inspect manually with: unsquashfs -l ${SQUASHFS}" >&2
  exit 1
fi
echo "[INFO] Found: ${MOD_PATH}"

echo "[INFO] Extracting ${MOD_PATH} from squashfs (this can take a minute)"
unsquashfs -d "${WORKDIR}/extracted" -f "${WORKDIR}/${SQUASHFS}" "${MOD_PATH}"

MODULES_DIR="${WORKDIR}/extracted/$(dirname "${MOD_PATH}")"
if [ ! -d "${MODULES_DIR}" ]; then
  echo "[ERROR] Extraction did not produce expected directory ${MODULES_DIR}" >&2
  exit 1
fi

KERNEL_VERSION="$(ls "${MODULES_DIR}")"
COUNT="$(ls "${MODULES_DIR}" | wc -l)"

if [ "${COUNT}" -ne 1 ]; then
  echo "[WARN] Expected exactly one kernel dir under /lib/modules, found ${COUNT}:" >&2
  ls "${MODULES_DIR}" >&2
fi

echo ""
echo "Harvester ${VERSION} (${ARCH}) kernel version: ${KERNEL_VERSION}"
