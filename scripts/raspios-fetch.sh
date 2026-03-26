#!/bin/bash
# scripts/raspios-fetch.sh
# Fetch Raspberry Pi OS kernel packages from the repository

set -e

echo "::group::Fetching package information from Raspberry Pi OS repository"

REPO_BASE="http://archive.raspberrypi.org/debian"
WORK_DIR="raspios-work"
mkdir -p "$WORK_DIR/debs"

# Map Alpine architecture to Raspberry Pi OS architecture
if [ "$ARCH" = "aarch64" ]; then
  FETCH_ARCH="arm64"
elif [ "$ARCH" = "armhf" ]; then
  FETCH_ARCH="armhf"
else
  FETCH_ARCH="$ARCH"
fi

echo "Architecture mapping: $ARCH (Alpine) -> $FETCH_ARCH (RasPiOS)"

# Download package list
echo "Downloading package list for ${FETCH_ARCH}..."
PACKAGES_URL="${REPO_BASE}/dists/${RASPIOS_DIST}/main/binary-${FETCH_ARCH}/Packages.gz"
echo "URL: ${PACKAGES_URL}"

if ! wget -O "${WORK_DIR}/Packages_${FETCH_ARCH}.gz" "${PACKAGES_URL}"; then
  echo "Failed to download package list for ${FETCH_ARCH}"
  exit 1
fi

gunzip -f "${WORK_DIR}/Packages_${FETCH_ARCH}.gz"

# Find latest kernel version
KERNEL_VERSION=$(grep "^Package: linux-image-" "${WORK_DIR}/Packages_${FETCH_ARCH}" | \
  sed -n 's/^Package: linux-image-\([0-9][0-9.]*+rpt[^-]*\)-rpi.*/\1/p' | \
  sort -V | tail -1)

echo "Latest kernel version: ${KERNEL_VERSION}"
echo "kernel_version=${KERNEL_VERSION}" >> $GITHUB_OUTPUT

# Function to download a package
download_package() {
  local package=$1
  local filename=$(awk -v pkg="$package" '
    BEGIN { RS = ""; FS = "\n" }
    {
      found = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "Package: " pkg) found = 1
        if (found && $i ~ /^Filename: /) {
          print substr($i, 11)
          exit
        }
      }
    }
  ' "${WORK_DIR}/Packages_${FETCH_ARCH}")
  
  if [ -n "$filename" ]; then
    local basename=$(basename "$filename")
    if [ ! -f "${WORK_DIR}/debs/$basename" ]; then
      echo "  Downloading ${package}..."
      wget -q --show-progress -O "${WORK_DIR}/debs/$basename" "${REPO_BASE}/${filename}"
      return 0
    fi
  else
    echo "  Package ${package} not found"
  fi
  return 1
}

# Function to download a package from arm64 repo
download_package_arm64() {
  local package=$1
  local filename=$(awk -v pkg="$package" '
    BEGIN { RS = ""; FS = "\n" }
    {
      found = 0
      for (i = 1; i <= NF; i++) {
        if ($i == "Package: " pkg) found = 1
        if (found && $i ~ /^Filename: /) {
          print substr($i, 11)
          exit
        }
      }
    }
  ' "${WORK_DIR}/Packages_arm64")
  
  if [ -n "$filename" ]; then
    local basename=$(basename "$filename")
    if [ ! -f "${WORK_DIR}/debs/$basename" ]; then
      echo "  Downloading ${package} (arm64)..."
      wget -q --show-progress -O "${WORK_DIR}/debs/$basename" "${REPO_BASE}/${filename}"
      return 0
    fi
  else
    echo "  Package ${package} not found in arm64 repo"
  fi
  return 1
}

# Determine what to download based on package_types
PACKAGES_TO_DOWNLOAD=""

if [ "$PACKAGE_TYPES" = "all" ] || [ "$PACKAGE_TYPES" = "kernel-only" ]; then
  # Add kernel packages for each variant
  for variant in $VARIANTS; do
    # Meta packages
    PACKAGES_TO_DOWNLOAD="$PACKAGES_TO_DOWNLOAD linux-image-rpi-${variant} linux-headers-rpi-${variant}"
    
    # Versioned packages
    if [ -n "$KERNEL_VERSION" ]; then
      PACKAGES_TO_DOWNLOAD="$PACKAGES_TO_DOWNLOAD linux-image-${KERNEL_VERSION}-rpi-${variant}"
      PACKAGES_TO_DOWNLOAD="$PACKAGES_TO_DOWNLOAD linux-headers-${KERNEL_VERSION}-rpi-${variant}"
    fi
  done
  
  # Common headers
  if [ -n "$KERNEL_VERSION" ]; then
    PACKAGES_TO_DOWNLOAD="$PACKAGES_TO_DOWNLOAD linux-headers-${KERNEL_VERSION}-common-rpi"
  fi
fi

# Firmware packages
if [ "$PACKAGE_TYPES" = "all" ] || [ "$PACKAGE_TYPES" = "firmware-only" ]; then
  echo "Checking for firmware packages..."

  for pkg in raspi-firmware raspberrypi-firmware firmware-brcm80211 firmware-misc-nonfree; do
    if grep -q "^Package: ${pkg}$" "${WORK_DIR}/Packages_${FETCH_ARCH}"; then
      echo "  Found firmware package: $pkg"
      PACKAGES_TO_DOWNLOAD="$PACKAGES_TO_DOWNLOAD $pkg"
    fi
  done

  # Fetch USB WiFi firmware from Debian non-free-firmware repository
  # These match the RPi OS kernel (Debian-based) rather than Alpine's versions
  echo ""
  echo "Fetching USB WiFi firmware from Debian ${RASPIOS_DIST} non-free-firmware..."
  DEBIAN_REPO_BASE="http://deb.debian.org/debian"
  DEBIAN_FW_PACKAGES_URL="${DEBIAN_REPO_BASE}/dists/${RASPIOS_DIST}/non-free-firmware/binary-${FETCH_ARCH}/Packages.gz"

  if wget -O "${WORK_DIR}/Packages_debian_fw_${FETCH_ARCH}.gz" "${DEBIAN_FW_PACKAGES_URL}" 2>/dev/null; then
    gunzip -f "${WORK_DIR}/Packages_debian_fw_${FETCH_ARCH}.gz"
    echo "  Downloaded Debian non-free-firmware package list for ${FETCH_ARCH}"

    for pkg in firmware-realtek firmware-atheros firmware-mediatek firmware-misc-nonfree; do
      filename=$(awk -v pkg="$pkg" '
        BEGIN { RS = ""; FS = "\n" }
        {
          found = 0
          for (i = 1; i <= NF; i++) {
            if ($i == "Package: " pkg) found = 1
            if (found && $i ~ /^Filename: /) {
              print substr($i, 11)
              exit
            }
          }
        }
      ' "${WORK_DIR}/Packages_debian_fw_${FETCH_ARCH}")

      if [ -n "$filename" ]; then
        deb_basename=$(basename "$filename")
        if [ ! -f "${WORK_DIR}/debs/$deb_basename" ]; then
          echo "  Downloading ${pkg} (${FETCH_ARCH})..."
          wget -q --show-progress -O "${WORK_DIR}/debs/$deb_basename" "${DEBIAN_REPO_BASE}/${filename}" || true
        fi
      else
        echo "  Package ${pkg} not found in Debian non-free-firmware"
      fi
    done
  else
    echo "  Warning: Could not fetch Debian non-free-firmware package list for ${FETCH_ARCH}"
  fi
fi

# Download packages
echo "Downloading packages..."
DOWNLOADED_COUNT=0
FAILED_COUNT=0

for pkg in $PACKAGES_TO_DOWNLOAD; do
  if download_package "$pkg"; then
    DOWNLOADED_COUNT=$((DOWNLOADED_COUNT + 1))
  else
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

echo "Downloaded $DOWNLOADED_COUNT packages, $FAILED_COUNT not found"

# On armhf, also fetch arm64 packages for v8 kernel and DTBs (including Pi 5)
if [ "$ARCH" = "armhf" ] && [ "$FETCH_ARCH" = "armhf" ]; then
  echo ""
  echo "Also fetching arm64 packages for v8 kernel and complete DTB collection (Pi 5 support)..."

  # Download arm64 package list
  PACKAGES_URL_ARM64="${REPO_BASE}/dists/${RASPIOS_DIST}/main/binary-arm64/Packages.gz"
  echo "Downloading arm64 package list..."

  if wget -O "${WORK_DIR}/Packages_arm64.gz" "${PACKAGES_URL_ARM64}"; then
    gunzip -f "${WORK_DIR}/Packages_arm64.gz"

    # Find the arm64 kernel version (should match armhf)
    ARM64_KERNEL_VERSION=$(grep "^Package: linux-image-" "${WORK_DIR}/Packages_arm64" | \
      sed -n 's/^Package: linux-image-\([0-9][0-9.]*+rpt[^-]*\)-rpi.*/\1/p' | \
      sort -V | tail -1)

    echo "arm64 kernel version: ${ARM64_KERNEL_VERSION}"

    # v8 kernel packages - the 64-bit kernel runs with 32-bit armhf userland
    ARM64_PACKAGES=""

    if [ -n "$ARM64_KERNEL_VERSION" ]; then
      ARM64_PACKAGES="linux-image-${ARM64_KERNEL_VERSION}-rpi-v8 linux-headers-${ARM64_KERNEL_VERSION}-rpi-v8 linux-headers-${ARM64_KERNEL_VERSION}-common-rpi"
    fi

    # Meta packages as fallback, plus 2712 for DTBs
    ARM64_PACKAGES="$ARM64_PACKAGES linux-image-rpi-v8 linux-headers-rpi-v8 linux-image-rpi-2712"

    # Download the arm64 packages
    for pkg in $ARM64_PACKAGES; do
      if grep -q "^Package: ${pkg}$" "${WORK_DIR}/Packages_arm64"; then
        echo "  Found arm64 package: $pkg"
        if download_package_arm64 "$pkg"; then
          echo "    Downloaded $pkg"
        fi
      fi
    done

    echo "ARM64 packages downloaded for v8 kernel and DTB extraction"
  else
    echo "Warning: Could not fetch arm64 package list - v8 kernel and Pi 5 DTBs may be missing"
  fi
fi

echo "::endgroup::"