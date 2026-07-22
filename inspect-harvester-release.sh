#!/usr/bin/env bash
# Extract information (kernel version, packages, or images) from a Harvester release without deploying a node.
# Downloads or extracts squashfs, and queries requested data.
#
# Requires: curl, unsquashfs (squashfs-tools)

set -euo pipefail

# Default values
ARCH="amd64"
KEEP=false
QUIET=false
PACKAGES=false
IMAGES=false
FILTER=""
FORCE_SQUASHFS=false
LOCAL_SQUASHFS=""

show_help() {
  cat << EOF
Usage: $0 [options] [version[,version...]]

Options:
  -a, --arch <arch>      Architecture: amd64 (default) | arm64
  -k, --keep             Keep the downloaded and extracted squashfs files
  -q, --quiet            Quiet mode: suppress progress messages and logs
  -p, --packages         List all installed RPM packages instead of kernel version
  -i, --images           List bundle container images instead of kernel version
  -f, --filter <pattern> Filter packages or images by a case-insensitive pattern
  --force-squashfs       Force image list extraction from squashfs (skip GitHub fast path)
  -s, --squashfs <file>  Read from a local squashfs file instead of downloading
  -h, --help             Show this help message

Examples:
  $0 v1.7.0
  $0 -a arm64 -k v1.7.0,v1.8.0
  $0 -p v1.8.1
  $0 -i -f longhorn v1.8.1
  $0 -s /path/to/rootfs.squashfs
  $0 -s /path/to/rootfs.squashfs -i -f longhorn
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
    -i|--images)
      IMAGES=true
      shift
      ;;
    -f|--filter)
      if [ -n "${2:-}" ]; then
        FILTER="$2"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    --force-squashfs)
      FORCE_SQUASHFS=true
      shift
      ;;
    -s|--squashfs)
      if [ -n "${2:-}" ]; then
        LOCAL_SQUASHFS="$2"
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
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

if [ -z "${LOCAL_SQUASHFS}" ] && [ $# -lt 1 ]; then
  echo "Error: Missing Harvester version argument or local --squashfs path" >&2
  show_help
fi

if [ -n "${LOCAL_SQUASHFS}" ]; then
  if [ ! -f "${LOCAL_SQUASHFS}" ]; then
    echo "Error: Squashfs file not found at ${LOCAL_SQUASHFS}" >&2
    exit 1
  fi
  if [ $# -gt 0 ]; then
    echo "Error: Cannot specify both a local squashfs file (-s) and a version argument ($1)" >&2
    exit 1
  fi
fi

if [ "$PACKAGES" = "true" ] && [ "$IMAGES" = "true" ]; then
  echo "Error: -p/--packages and -i/--images are mutually exclusive" >&2
  exit 1
fi

if [ -n "${FILTER}" ] && [ "$PACKAGES" = "false" ] && [ "$IMAGES" = "false" ]; then
  echo "Error: --filter can only be used with --packages or --images" >&2
  exit 1
fi

if [ "$FORCE_SQUASHFS" = "true" ] && [ "$IMAGES" = "false" ]; then
  echo "Error: --force-squashfs can only be used with -i/--images" >&2
  exit 1
fi

# We support comma-separated list of versions
if [ -n "${LOCAL_SQUASHFS}" ]; then
  VERSIONS_ARRAY=("local")
else
  IFS=',' read -r -a VERSIONS_ARRAY <<< "$1"
fi

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

  FETCHED=false
  IMAGE_LIST_FILE="${VERSION_DIR}/harvester-images-list.txt"

  if [ -n "${LOCAL_SQUASHFS}" ]; then
    SQUASHFS_PATH="${LOCAL_SQUASHFS}"
  else
    BASE_URL="https://releases.rancher.com/harvester/${VERSION}"
    SQUASHFS="harvester-${VERSION}-rootfs-${ARCH}.squashfs"
    URL="${BASE_URL}/${SQUASHFS}"
    SHA_URL="${BASE_URL}/harvester-${VERSION}-${ARCH}.sha512"
    SQUASHFS_PATH="${VERSION_DIR}/${SQUASHFS}"

    if [ "$IMAGES" = "true" ] && [ "$FORCE_SQUASHFS" = "false" ]; then
      log_info "Attempting to fetch image list directly from GitHub releases (fast path)"
      GITHUB_URLS=(
        "https://github.com/harvester/harvester/releases/download/${VERSION}/harvester-images-list-${ARCH}.txt"
        "https://github.com/harvester/harvester/releases/download/${VERSION}/harvester-images-list.txt"
      )
      
      for G_URL in "${GITHUB_URLS[@]}"; do
        log_info "Trying URL: ${G_URL}"
        CURL_IMG_ARGS=("-fSL" "-o" "${IMAGE_LIST_FILE}")
        if [ "$QUIET" = "true" ]; then
          CURL_IMG_ARGS+=("-s")
        fi
        if curl "${CURL_IMG_ARGS[@]}" "${G_URL}"; then
          log_info "Successfully fetched image list from GitHub"
          FETCHED=true
          break
        fi
      done

      if [ "$FETCHED" = "true" ]; then
        IMG_LIST="$(grep -vE '^\s*#|^\s*$' "${IMAGE_LIST_FILE}" | sort -u || true)"
        if [ -n "${FILTER}" ]; then
          IMG_LIST="$(echo "${IMG_LIST}" | grep -iE "${FILTER}" || true)"
        fi
        
        if [ "$QUIET" = "true" ]; then
          if [ "${#VERSIONS_ARRAY[@]}" -eq 1 ]; then
            echo "${IMG_LIST}"
          else
            echo "${IMG_LIST}" | sed "s/^/${VERSION}: /"
          fi
        else
          echo ""
          echo "Harvester ${VERSION} (${ARCH}) images:"
          echo "${IMG_LIST}"
        fi
        continue
      fi
    fi

    log_info "Fetching ${URL}"
    CURL_ARGS=("-fSL" "-o" "${SQUASHFS_PATH}")
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
          ACTUAL="$(sha512sum "${SQUASHFS_PATH}" | awk '{print $1}')"
          if [ "${EXPECTED}" != "${ACTUAL}" ]; then
            log_error "Checksum mismatch for ${SQUASHFS}. Expected ${EXPECTED}, got ${ACTUAL}"
            exit 1
          fi
          log_info "Checksum OK"
        elif command -v shasum >/dev/null 2>&1; then
          ACTUAL="$(shasum -a 512 "${SQUASHFS_PATH}" | awk '{print $1}')"
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
  fi

  if [ "$IMAGES" = "true" ]; then
    log_info "Extracting image list from squashfs"
    UNSQUASH_ARGS=("-l" "${SQUASHFS_PATH}")
    if [ "$QUIET" = "true" ]; then
      IMG_PATH="$(unsquashfs "${UNSQUASH_ARGS[@]}" 2>/dev/null \
        | grep -iE 'harvester-images|image_list|images.*\.txt' \
        | sed -e 's#^/##' -e 's#^squashfs-root/##' \
        | sort -u | head -1 || true)"
    else
      IMG_PATH="$(unsquashfs "${UNSQUASH_ARGS[@]}" \
        | grep -iE 'harvester-images|image_list|images.*\.txt' \
        | sed -e 's#^/##' -e 's#^squashfs-root/##' \
        | sort -u | head -1 || true)"
    fi

    if [ -z "${IMG_PATH}" ]; then
      log_warn "Could not find any image list file inside squashfs for ${VERSION}"
      log_info "Attempting to fetch image list from GitHub releases as a fallback..."
      
      GITHUB_URLS=(
        "https://github.com/harvester/harvester/releases/download/${VERSION}/harvester-images-list-${ARCH}.txt"
        "https://github.com/harvester/harvester/releases/download/${VERSION}/harvester-images-list.txt"
      )
      
      FALLBACK_FETCHED=false
      for G_URL in "${GITHUB_URLS[@]}"; do
        log_info "Trying URL: ${G_URL}"
        CURL_IMG_ARGS=("-fSL" "-o" "${IMAGE_LIST_FILE}")
        if [ "$QUIET" = "true" ]; then
          CURL_IMG_ARGS+=("-s")
        fi
        if curl "${CURL_IMG_ARGS[@]}" "${G_URL}"; then
          log_info "Successfully fetched image list from GitHub as fallback"
          FALLBACK_FETCHED=true
          break
        fi
      done
      
      if [ "$FALLBACK_FETCHED" = "false" ]; then
        log_error "Could not find image list file inside squashfs or on GitHub releases"
        if [ -n "${LOCAL_SQUASHFS}" ]; then
          echo "Note: The standard base OS rootfs squashfs does not package the image list file." >&2
          echo "Please run the script specifying a version instead of a local file to let it download" >&2
          echo "or make sure you specify a full installation ISO squashfs." >&2
        fi
        exit 1
      fi
    else
      log_info "Found image list: ${IMG_PATH}"

      log_info "Extracting ${IMG_PATH} from squashfs"
      EXTRACT_IMG_ARGS=("-d" "${VERSION_DIR}/extracted_img" "-f" "${SQUASHFS_PATH}" "${IMG_PATH}")
      if [ "$QUIET" = "true" ]; then
        unsquashfs "${EXTRACT_IMG_ARGS[@]}" >/dev/null 2>&1
      else
        unsquashfs "${EXTRACT_IMG_ARGS[@]}"
      fi

      cp "${VERSION_DIR}/extracted_img/${IMG_PATH}" "${IMAGE_LIST_FILE}"
    fi

    IMG_LIST="$(grep -vE '^\s*#|^\s*$' "${IMAGE_LIST_FILE}" | sort -u || true)"
    if [ -n "${FILTER}" ]; then
      IMG_LIST="$(echo "${IMG_LIST}" | grep -iE "${FILTER}" || true)"
    fi

    if [ "$QUIET" = "true" ]; then
      if [ "${#VERSIONS_ARRAY[@]}" -eq 1 ]; then
        echo "${IMG_LIST}"
      else
        echo "${IMG_LIST}" | sed "s/^/${VERSION}: /"
      fi
    else
      echo ""
      echo "Harvester ${VERSION} (${ARCH}) images:"
      echo "${IMG_LIST}"
    fi
    continue
  fi

  if [ "$PACKAGES" = "true" ]; then
    log_info "Extracting RPM database from squashfs"
    # Try to extract usr/lib/sysimage/rpm first
    EXTRACT_RPM_ARGS=("-d" "${VERSION_DIR}/extracted_rpm" "-f" "${SQUASHFS_PATH}" "usr/lib/sysimage/rpm")
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

    if [ -n "${FILTER}" ]; then
      PKG_LIST="$(echo "${PKG_LIST}" | grep -iE "${FILTER}" || true)"
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
  UNSQUASH_ARGS=("-l" "${SQUASHFS_PATH}")
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
  EXTRACT_ARGS=("-d" "${VERSION_DIR}/extracted" "-f" "${SQUASHFS_PATH}" "${MOD_PATH}")
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
