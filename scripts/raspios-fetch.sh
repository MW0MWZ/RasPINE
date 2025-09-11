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

# Determine what to download based on package_types
PACKAGES_TO_DOWNLOAD=""

# Only add kernel packages since firmware packages aren't being found
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

# Try to find firmware packages - check what's actually available
if [ "$PACKAGE_TYPES" = "all" ] || [ "$PACKAGE_TYPES" = "firmware-only" ]; then
  echo "Checking for firmware packages..."
  
  # List all raspberry/raspi related packages to see what's available
  echo "Available raspberry/raspi packages:"
  grep "^Package: raspi" "${WORK_DIR}/Packages_${FETCH_ARCH}" | head -20 || true
  grep "^Package: raspberry" "${WORK_DIR}/Packages_${FETCH_ARCH}" | head -20 || true
  
  # Try the common firmware package names
  for pkg in raspi-firmware raspberrypi-firmware firmware-brcm80211 firmware-misc-nonfree; do
    if grep -q "^Package: ${pkg}$" "${WORK_DIR}/Packages_${FETCH_ARCH}"; then
      echo "  Found firmware package: $pkg"
      PACKAGES_TO_DOWNLOAD="$PACKAGES_TO_DOWNLOAD $pkg"
    fi
  done
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
echo "::endgroup::"