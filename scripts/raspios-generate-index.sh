#!/bin/bash
# scripts/raspios-generate-index.sh
# Generate repository index including ALL packages (existing + new)

set -e

ALPINE_VERSION="${1:-3.22}"
ARCH="${2:-$ARCH}"
PLATFORM="${3:-$PLATFORM}"

echo "::group::Generating repository index for Alpine ${ALPINE_VERSION} ${ARCH}"

REPO_DIR="repo/v${ALPINE_VERSION}/community/${ARCH}"
GH_PAGES_DIR="gh-pages-check/v${ALPINE_VERSION}/community/${ARCH}"
TEMP_WORK_DIR=$(mktemp -d)
trap "rm -rf $TEMP_WORK_DIR" EXIT

# Create a temporary directory with ALL packages
mkdir -p "$TEMP_WORK_DIR/packages"

# First, copy ALL existing packages from gh-pages
if [ -d "$GH_PAGES_DIR" ]; then
  echo "Copying existing packages from gh-pages..."
  for pkg in "$GH_PAGES_DIR"/*.apk; do
    if [ -f "$pkg" ]; then
      echo "  - $(basename "$pkg")"
      cp "$pkg" "$TEMP_WORK_DIR/packages/"
    fi
  done
  echo "Copied $(ls -1 $GH_PAGES_DIR/*.apk 2>/dev/null | wc -l) existing packages"
fi

# Then copy/overwrite with NEW packages (these take precedence)
if [ -d "$REPO_DIR" ]; then
  echo "Adding new packages..."
  for pkg in "$REPO_DIR"/*.apk; do
    if [ -f "$pkg" ]; then
      echo "  + $(basename "$pkg")"
      cp "$pkg" "$TEMP_WORK_DIR/packages/"
    fi
  done
  echo "Added $(ls -1 $REPO_DIR/*.apk 2>/dev/null | wc -l) new packages"
fi

# Now copy everything back to the repo directory
mkdir -p "$REPO_DIR"
cp "$TEMP_WORK_DIR/packages"/*.apk "$REPO_DIR/" 2>/dev/null || true

TOTAL_PACKAGES=$(ls -1 "$REPO_DIR"/*.apk 2>/dev/null | wc -l)
echo "Total packages to index: $TOTAL_PACKAGES"

if [ "$TOTAL_PACKAGES" -eq 0 ]; then
  echo "No packages found to index"
  exit 0
fi

# List all packages that will be indexed
echo "Packages in repository:"
ls -1 "$REPO_DIR"/*.apk | xargs -n1 basename | sort

# Setup keys
TEMP_KEY_DIR=$(mktemp -d)
trap "rm -rf $TEMP_KEY_DIR" EXIT

echo "$APK_PRIVATE_KEY" > "$TEMP_KEY_DIR/hamradio.rsa"
cp keys/hamradio.rsa.pub "$TEMP_KEY_DIR/"

# Generate index for ALL packages
echo "Generating APKINDEX..."
docker run --rm \
  --platform "$PLATFORM" \
  -v "$TEMP_KEY_DIR:/keys:ro" \
  -v "$(pwd)/$REPO_DIR:/repo" \
  "alpine:${ALPINE_VERSION}" \
  sh -c '
    set -e
    apk add --no-cache alpine-sdk
    mkdir -p /root/.abuild
    echo "PACKAGER_PRIVKEY=\"/keys/hamradio.rsa\"" > /root/.abuild/abuild.conf
    cp /keys/hamradio.rsa.pub /etc/apk/keys/
    cd /repo
    
    # Remove any old index
    rm -f APKINDEX.tar.gz APKINDEX.unsigned.tar.gz
    
    # Count packages
    echo "Indexing $(ls -1 *.apk 2>/dev/null | wc -l) packages..."
    
    # Generate fresh index for ALL packages
    apk index -o APKINDEX.unsigned.tar.gz *.apk
    abuild-sign -k /keys/hamradio.rsa APKINDEX.unsigned.tar.gz
    mv APKINDEX.unsigned.tar.gz APKINDEX.tar.gz
    
    # Verify by extracting and counting entries
    echo "Verification:"
    tar -xzOf APKINDEX.tar.gz APKINDEX | grep -c "^P:" || true
    echo " packages in index"
  '

echo "Index generation complete for ${ARCH}"
echo "::endgroup::"