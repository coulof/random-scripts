#!/usr/bin/env bash
# Extract kernel version from a Harvester release without deploying a node.
# Downloads the rootfs squashfs, extracts only /lib/modules, reads dir name.
#
# Requires: curl, unsquashfs (squashfs-tools)

set -euo pipefail

# Default values
ARCH="amd64"
KEEP=false
QUIET=false
PACKAGES=false

show_help() {
  cat << EOF
Usage: $0 [options] <version[,version...]>

Options:
  -a, --arch <arch>      Architecture: amd64 (default) | arm64
  -k, --keep             Keep the downloaded and extracted squashfs files
  -q, --quiet            Quiet mode: suppress progress messages and logs
  -p, --packages         List all installed RPM packages instead of kernel version
  -h, --help             Show this help message

Examples:
  $0 v1.7.0
  $0 -a arm64 -k v1.7.0,v1.8.0
  $0 -p v1.3.1
EOF
  exit 0
}

# Parse options
PARAMS=""
while (( "$#" )); do
  case "$1" in
    -h|--help)
      show_help
      ;;
    -a|--arch)
      if [ -n "${2:-}" ]; then
        ARCH="$2"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -k|--keep)
      KEEP=true
      shift
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -p|--packages)
      PACKAGES=true
      shift
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# Eval set to restore positional arguments
eval set -- "$PARAMS"

if [ $# -lt 1 ]; then
  echo "Error: Missing Harvester version argument" >&2
  show_help
fi

# We support comma-separated list of versions
IFS=',' read -r -a VERSIONS_ARRAY <<< "$1"

# Logging helpers
log_info() {
  if [ "$QUIET" = false ]; then
    echo "[INFO] $1" >&2
  fi
}

log_warn() {
  if [ "$QUIET" = false ]; then
    echo "[WARN] $1" >&2
  fi
}

log_error() {
  echo "[ERROR] $1" >&2
}

# Check requirements
command -v unsquashfs >/dev/null 2>&1 || {
  log_error "unsquashfs not found. Install squashfs-tools."
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  log_error "curl not found. Please install curl."
  exit 1
}

# Temporary workspace directory
WORKDIR="$(mktemp -d)"

cleanup() {
  if [ "$KEEP" = "true" ]; then
    log_info "Keeping downloaded and extracted files in: ${WORKDIR}"
  else
    rm -rf "${WORKDIR}"
  fi
}
trap cleanup EXIT

for VERSION in "${VERSIONS_ARRAY[@]}"; do
  VERSION_DIR="${WORKDIR}/${VERSION}"
  mkdir -p "${VERSION_DIR}"

  BASE_URL="https://releases.rancher.com/harvester/${VERSION}"
  SQUASHFS="harvester-${VERSION}-rootfs-${ARCH}.squashfs"
  URL="${BASE_URL}/${SQUASHFS}"
  SHA_URL="${BASE_URL}/harvester-${VERSION}-${ARCH}.sha512"

  log_info "Fetching ${URL}"
  CURL_ARGS=("-fSL" "-o" "${VERSION_DIR}/${SQUASHFS}")
  if [ "$QUIET" = "true" ]; then
    CURL_ARGS+=("-s")
  else
    CURL_ARGS+=("--progress-bar")
  fi
  
  if ! curl "${CURL_ARGS[@]}" "${URL}"; then
    log_error "Failed to fetch ${URL}"
    exit 1
  fi

  # Optional checksum verification
  log_info "Verifying checksum"
  CURL_SHA_ARGS=("-fsSL" "-o" "${VERSION_DIR}/checksums.sha512")
  if [ "$QUIET" = "true" ]; then
    CURL_SHA_ARGS+=("-s")
  fi
  if curl "${CURL_SHA_ARGS[@]}" "${SHA_URL}"; then
    EXPECTED="$(grep "${SQUASHFS}" "${VERSION_DIR}/checksums.sha512" | awk '{print $1}' || true)"
    if [ -n "${EXPECTED}" ]; then
      if command -v sha512sum >/dev/null 2>&1; then
        ACTUAL="$(sha512sum "${VERSION_DIR}/${SQUASHFS}" | awk '{print $1}')"
        if [ "${EXPECTED}" != "${ACTUAL}" ]; then
          log_error "Checksum mismatch for ${SQUASHFS}. Expected ${EXPECTED}, got ${ACTUAL}"
          exit 1
        fi
        log_info "Checksum OK"
      elif command -v shasum >/dev/null 2>&1; then
        ACTUAL="$(shasum -a 512 "${VERSION_DIR}/${SQUASHFS}" | awk '{print $1}')"
        if [ "${EXPECTED}" != "${ACTUAL}" ]; then
          log_error "Checksum mismatch for ${SQUASHFS}. Expected ${EXPECTED}, got ${ACTUAL}"
          exit 1
        fi
        log_info "Checksum OK"
      else
        log_warn "Neither sha512sum nor shasum available, skipping checksum verification"
      fi
    else
      log_warn "Could not find ${SQUASHFS} entry in sha512 file, skipping verification"
    fi
  else
    log_warn "Could not fetch sha512 file, skipping verification"
  fi

  if [ "$PACKAGES" = "true" ]; then
    log_info "Extracting RPM database from squashfs"
    # Try to extract usr/lib/sysimage/rpm first
    EXTRACT_RPM_ARGS=("-d" "${VERSION_DIR}/extracted_rpm" "-f" "${VERSION_DIR}/${SQUASHFS}" "usr/lib/sysimage/rpm")
    if [ "$QUIET" = "true" ]; then
      unsquashfs "${EXTRACT_RPM_ARGS[@]}" >/dev/null 2>&1 || true
    else
      unsquashfs "${EXTRACT_RPM_ARGS[@]}" || true
    fi

    RPM_DB_PATH="${VERSION_DIR}/extracted_rpm/usr/lib/sysimage/rpm"

    # Fallback to var/lib/rpm if usr/lib/sysimage/rpm wasn't found/extracted
    if [ ! -d "${RPM_DB_PATH}" ]; then
      log_info "usr/lib/sysimage/rpm not found, trying var/lib/rpm fallback"
      EXTRACT_RPM_ARGS_FALLBACK=("-d" "${VERSION_DIR}/extracted_rpm" "-f" "${VERSION_DIR}/${SQUASHFS}" "var/lib/rpm")
      if [ "$QUIET" = "true" ]; then
        unsquashfs "${EXTRACT_RPM_ARGS_FALLBACK[@]}" >/dev/null 2>&1 || true
      else
        unsquashfs "${EXTRACT_RPM_ARGS_FALLBACK[@]}" || true
      fi
      RPM_DB_PATH="${VERSION_DIR}/extracted_rpm/var/lib/rpm"
    fi

    if [ ! -d "${RPM_DB_PATH}" ]; then
      log_error "Extraction did not produce RPM database directory at usr/lib/sysimage/rpm or var/lib/rpm"
      exit 1
    fi

    # Query RPM packages
    if command -v rpm >/dev/null 2>&1; then
      log_info "Querying RPM database natively"
      if [ "$QUIET" = "true" ]; then
        PKG_LIST="$(rpm --dbpath "${RPM_DB_PATH}" -qa --queryformat "%{NAME} %{VERSION}-%{RELEASE}\n" 2>/dev/null | sort)"
      else
        PKG_LIST="$(rpm --dbpath "${RPM_DB_PATH}" -qa --queryformat "%{NAME} %{VERSION}-%{RELEASE}\n" | sort)"
      fi
    elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      log_info "Querying RPM database via Docker container (using SUSE BCI image)"
      if [ "$QUIET" = "true" ]; then
        PKG_LIST="$(docker run --rm -v "${RPM_DB_PATH}:/extracted_rpm:ro" registry.suse.com/bci/bci-base:15.5 rpm --dbpath /extracted_rpm -qa --queryformat "%{NAME} %{VERSION}-%{RELEASE}\n" 2>/dev/null | sort)"
      else
        PKG_LIST="$(docker run --rm -v "${RPM_DB_PATH}:/extracted_rpm:ro" registry.suse.com/bci/bci-base:15.5 rpm --dbpath /extracted_rpm -qa --queryformat "%{NAME} %{VERSION}-%{RELEASE}\n" | sort)"
      fi
    elif command -v podman >/dev/null 2>&1; then
      log_info "Querying RPM database via Podman container (using SUSE BCI image)"
      if [ "$QUIET" = "true" ]; then
        PKG_LIST="$(podman run --rm -v "${RPM_DB_PATH}:/extracted_rpm:ro" registry.suse.com/bci/bci-base:15.5 rpm --dbpath /extracted_rpm -qa --queryformat "%{NAME} %{VERSION}-%{RELEASE}\n" 2>/dev/null | sort)"
      else
        PKG_LIST="$(podman run --rm -v "${RPM_DB_PATH}:/extracted_rpm:ro" registry.suse.com/bci/bci-base:15.5 rpm --dbpath /extracted_rpm -qa --queryformat "%{NAME} %{VERSION}-%{RELEASE}\n" | sort)"
      fi
    else
      log_error "To query packages, you must either:"
      echo "  1. Install 'rpm' on your host (e.g., 'brew install rpm' on macOS or 'apt install rpm' on Debian/Ubuntu)" >&2
      echo "  2. Have a running Docker or Podman engine to use the automated container-based query." >&2
      exit 1
    fi

    if [ "$QUIET" = "true" ]; then
      if [ "${#VERSIONS_ARRAY[@]}" -eq 1 ]; then
        echo "${PKG_LIST}"
      else
        # Prefix each line with VERSION if multiple versions are requested
        echo "${PKG_LIST}" | sed "s/^/${VERSION}: /"
      fi
    else
      echo ""
      echo "Harvester ${VERSION} (${ARCH}) packages:"
      echo "${PKG_LIST}"
    fi
    continue
  fi

  log_info "Locating lib/modules path inside squashfs (usr-merge means it may be usr/lib/modules)"
  
  # Hide stderr if quiet
  UNSQUASH_ARGS=("-l" "${VERSION_DIR}/${SQUASHFS}")
  if [ "$QUIET" = "true" ]; then
    MOD_PATH="$(unsquashfs "${UNSQUASH_ARGS[@]}" 2>/dev/null \
      | grep -oE '[^[:space:]]*lib/modules/[^/[:space:]]+' \
      | sed -e 's#^/##' -e 's#^squashfs-root/##' \
      | sort -u | head -1 || true)"
  else
    MOD_PATH="$(unsquashfs "${UNSQUASH_ARGS[@]}" \
      | grep -oE '[^[:space:]]*lib/modules/[^/[:space:]]+' \
      | sed -e 's#^/##' -e 's#^squashfs-root/##' \
      | sort -u | head -1 || true)"
  fi

  if [ -z "${MOD_PATH}" ]; then
    log_error "Could not find any */lib/modules/* path in squashfs listing for ${VERSION} — layout differs for this release"
    exit 1
  fi
  log_info "Found: ${MOD_PATH}"

  log_info "Extracting ${MOD_PATH} from squashfs"
  EXTRACT_ARGS=("-d" "${VERSION_DIR}/extracted" "-f" "${VERSION_DIR}/${SQUASHFS}" "${MOD_PATH}")
  if [ "$QUIET" = "true" ]; then
    unsquashfs "${EXTRACT_ARGS[@]}" >/dev/null 2>&1
  else
    unsquashfs "${EXTRACT_ARGS[@]}"
  fi

  MODULES_DIR="${VERSION_DIR}/extracted/$(dirname "${MOD_PATH}")"
  if [ ! -d "${MODULES_DIR}" ]; then
    log_error "Extraction did not produce expected directory ${MODULES_DIR}"
    exit 1
  fi

  KERNEL_VERSION="$(ls "${MODULES_DIR}")"
  COUNT="$(ls "${MODULES_DIR}" | wc -l)"

  if [ "${COUNT}" -ne 1 ]; then
    log_warn "Expected exactly one kernel dir under /lib/modules, found ${COUNT}:"
    if [ "$QUIET" = "false" ]; then
      ls "${MODULES_DIR}" >&2
    fi
  fi

  if [ "$QUIET" = "true" ]; then
    if [ "${#VERSIONS_ARRAY[@]}" -eq 1 ]; then
      echo "${KERNEL_VERSION}"
    else
      echo "${VERSION}: ${KERNEL_VERSION}"
    fi
  else
    echo ""
    echo "Harvester ${VERSION} (${ARCH}) kernel version: ${KERNEL_VERSION}"
  fi
done
