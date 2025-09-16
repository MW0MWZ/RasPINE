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

echo "$APK_PRIVATE_KEY" > "$TEMP_KEY_DIR/raspine.rsa"
cp keys/raspine.rsa.pub "$TEMP_KEY_DIR/raspine.rsa.pub"
chmod 600 "$TEMP_KEY_DIR/raspine.rsa"
chmod 644 "$TEMP_KEY_DIR/raspine.rsa.pub"

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
        cp /keys/raspine.rsa.pub /etc/apk/keys/
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
      cp /keys/raspine.rsa /home/builder/.abuild/
      cp /keys/raspine.rsa.pub /home/builder/.abuild/
      chown -R builder:builder /home/builder/.abuild
      chmod 600 /home/builder/.abuild/raspine.rsa
      chmod 644 /home/builder/.abuild/raspine.rsa.pub
      
      # Configure abuild to use our key and sign packages
      cat > /home/builder/.abuild/abuild.conf << CONF
PACKAGER="Andy Taylor <andy@mw0mwz.co.uk>"
PACKAGER_PRIVKEY="/home/builder/.abuild/raspine.rsa"
CONF
      chown builder:builder /home/builder/.abuild/abuild.conf
      
      # Install public key system-wide for package verification
      cp /keys/raspine.rsa.pub /etc/apk/keys/
      
      # Also install the key with the correct name format that APK expects
      # APK expects keys named by their fingerprint
      KEY_NAME=$(openssl rsa -in /keys/raspine.rsa -pubout 2>/dev/null | \
                 openssl rsa -pubin -outform DER 2>/dev/null | \
                 openssl dgst -sha256 | \
                 sed "s/^.* //" | \
                 head -c 16)
      
      if [ -n "$KEY_NAME" ]; then
        echo "Installing key as /etc/apk/keys/${KEY_NAME}.rsa.pub"
        cp /keys/raspine.rsa.pub "/etc/apk/keys/${KEY_NAME}.rsa.pub" 2>/dev/null || true
      fi
      
      # Check if we have any install scripts and ensure they are executable
      cd /home/builder/package
      for script in *.post-install *.pre-install *.post-upgrade *.pre-upgrade *.post-deinstall *.pre-deinstall; do
        if [ -f "$script" ]; then
          echo "Found install script: $script"
          chmod +x "$script"
          chown builder:builder "$script"
        fi
      done
      
      # Build the package with signing
      echo "Building package with abuild..."
      su builder -c "cd /home/builder/package && abuild -r"
      
      # The packages should now be signed. Copy them to output
      if [ -d "/home/builder/packages" ]; then
        echo "Copying built packages to output..."
        find /home/builder/packages -name "*.apk" -type f | while read apk; do
          echo "  Copying $(basename $apk)"
          cp "$apk" /output/
        done
        
        # Verify signatures on the packages we just built
        echo "Verifying package signatures..."
        cd /output
        for apk in *.apk; do
          if [ -f "$apk" ]; then
            # Extract the signature from the APK
            tar -xOf "$apk" .SIGN.RSA.raspine.rsa.pub >/dev/null 2>&1 || {
              echo "  WARNING: $apk appears to be unsigned!"
              # Try to sign it manually
              echo "  Attempting to sign $apk manually..."
              abuild-sign -k /keys/raspine.rsa "$apk" || echo "    Manual signing failed"
            }
          fi
        done
      else
        echo "ERROR: No packages directory found after build"
        ls -la /home/builder/
        exit 1
      fi
    '
done

echo ""
echo "Built packages:"
ls -la "$REPO_DIR"/*.apk 2>/dev/null || echo "No packages built"

# Final verification that packages are signed
echo ""
echo "Verifying all packages are signed..."
for apk in "$REPO_DIR"/*.apk; do
  [ -f "$apk" ] || continue
  
  # Check if package contains signature
  if ! tar -tzf "$apk" 2>/dev/null | grep -q "^\.SIGN\.RSA\."; then
    echo "ERROR: $(basename $apk) is NOT signed!"
    
    # Attempt to sign it here as a fallback
    echo "Attempting emergency signing of $(basename $apk)..."
    docker run --rm \
      -v "$(pwd)/$REPO_DIR:/packages" \
      -v "$TEMP_KEY_DIR:/keys:ro" \
      alpine:${ALPINE_VERSION} \
      sh -c "
        apk add --no-cache alpine-sdk
        cd /packages
        abuild-sign -k /keys/raspine.rsa $(basename $apk)
      "
  else
    echo "✓ $(basename $apk) is signed"
  fi
done

echo "::endgroup::"