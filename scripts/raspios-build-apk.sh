#!/bin/bash
# scripts/raspios-build-apk.sh
# Build APK packages from APKBUILDs

set -e

echo "::group::Building APK packages"

OUTPUT_DIR="raspios-apk-staging"
APKBUILD_DIR="${OUTPUT_DIR}/apkbuilds"
REPO_DIR="repo/v${ALPINE_VERSION}/community/${ARCH}"

mkdir -p "$REPO_DIR"

# Setup keys
TEMP_KEY_DIR=$(mktemp -d)
trap "rm -rf $TEMP_KEY_DIR" EXIT

echo "$APK_PRIVATE_KEY" > "$TEMP_KEY_DIR/hamradio.rsa"
cp keys/hamradio.rsa.pub "$TEMP_KEY_DIR/hamradio.rsa.pub"

# Build each package
for pkg_dir in ${APKBUILD_DIR}/*/; do
  [ -d "$pkg_dir" ] || continue
  
  PKG_NAME=$(basename "$pkg_dir")
  echo "Building ${PKG_NAME}..."
  
  # Build in Docker with proper abuild setup
  docker run --rm \
    --platform "$PLATFORM" \
    -v "$(pwd)/$pkg_dir:/build" \
    -v "$TEMP_KEY_DIR:/keys:ro" \
    -v "$(pwd)/$REPO_DIR:/output" \
    "alpine:${ALPINE_VERSION}" \
    sh -c '
      set -e
      
      # Install build tools
      apk add --no-cache alpine-sdk sudo
      
      # Add the custom repository if we have already built some packages
      if [ -d "/output" ] && ls /output/*.apk >/dev/null 2>&1; then
        echo "Adding local repository for dependencies..."
        echo "/output" >> /etc/apk/repositories
        cp /keys/hamradio.rsa.pub /etc/apk/keys/
        apk update || true
      fi
      
      # For kernel packages, ensure mkinitfs is available
      if echo "'$PKG_NAME'" | grep -q "raspios-kernel"; then
        # mkinitfs is in the community repository
        echo "https://dl-cdn.alpinelinux.org/alpine/v'${ALPINE_VERSION}'/community" >> /etc/apk/repositories
        apk update
        # Install mkinitfs so the dependency check passes
        apk add --no-cache mkinitfs || true
      fi
      
      # Create builder user
      adduser -D builder
      addgroup builder abuild
      echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
      
      # Setup builder home with package files
      mkdir -p /home/builder/package
      cp -r /build/* /home/builder/package/
      chown -R builder:builder /home/builder
      
      # Setup abuild keys
      mkdir -p /home/builder/.abuild
      cp /keys/hamradio.rsa /home/builder/.abuild/
      cp /keys/hamradio.rsa.pub /home/builder/.abuild/
      chown -R builder:builder /home/builder/.abuild
      chmod 600 /home/builder/.abuild/hamradio.rsa
      chmod 644 /home/builder/.abuild/hamradio.rsa.pub
      
      # Configure abuild
      cat > /home/builder/.abuild/abuild.conf << CONF
PACKAGER_PRIVKEY="/home/builder/.abuild/hamradio.rsa"
CONF
      chown builder:builder /home/builder/.abuild/abuild.conf
      
      # Install public key for package verification
      cp /keys/hamradio.rsa.pub /etc/apk/keys/
      
      # Check if we have any install scripts and ensure they are executable
      cd /home/builder/package
      for script in *.post-install *.pre-install *.post-upgrade *.pre-upgrade *.post-deinstall *.pre-deinstall; do
        if [ -f "$script" ]; then
          echo "Found install script: $script"
          chmod +x "$script"
          chown builder:builder "$script"
        fi
      done
      
      # For packages with custom dependencies, we might need to skip dependency checking
      # or use nodeps for the dependency resolution
      if echo "'$PKG_NAME'" | grep -q "raspios-kernel"; then
        # Modify APKBUILD to make raspios-firmware optional at build time
        sed -i "s/^depends=\"raspios-firmware mkinitfs\"/depends=\"mkinitfs\"/" APKBUILD
        echo "install_if=\"raspios-firmware\"" >> APKBUILD
      fi
      
      # Build the package
      su builder -c "abuild -r"
      
      # Copy built packages to output
      if [ -d "/home/builder/packages" ]; then
        find /home/builder/packages -name "*.apk" -type f -exec cp {} /output/ \;
      fi
    '
done

echo ""
echo "Built packages:"
ls -la "$REPO_DIR"/*.apk 2>/dev/null || echo "No packages built"

echo "::endgroup::"