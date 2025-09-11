#!/bin/bash
# scripts/raspios-apkbuild.sh
# Create APKBUILD files for Raspberry Pi OS packages

set -e

echo "::group::Creating APKBUILD files"

OUTPUT_DIR="raspios-apk-staging"
APKBUILD_DIR="${OUTPUT_DIR}/apkbuilds"
mkdir -p "$APKBUILD_DIR"

# Get current date for version
PKG_DATE=$(date +%Y%m%d)

# Use kernel version if available, otherwise use date
if [ -n "$KERNEL_VERSION" ]; then
  # Extract just the numeric version part (e.g., 6.12.34 from 6.12.34+rpt)
  PKG_VERSION=$(echo "$KERNEL_VERSION" | sed 's/+.*//' | sed 's/-.*//')
  FULL_VERSION="$KERNEL_VERSION"
else
  PKG_VERSION="${PKG_DATE}"
  FULL_VERSION="${PKG_DATE}"
fi

echo "Original kernel version: $KERNEL_VERSION"
echo "Alpine-compatible version: $PKG_VERSION"

# Function to determine release number by checking existing packages
get_release_number() {
  local package_name=$1
  local package_version=$2
  local release_num=0
  
  # Check if we're in a GitHub Actions environment and have access to gh-pages
  if [ -d "gh-pages-check" ]; then
    # Check all architectures and Alpine versions for existing packages
    for version in 3.22 3.21; do
      for arch in x86_64 armhf aarch64; do
        GH_PAGES_DIR="gh-pages-check/v${version}/community/${arch}"
        if [ -d "$GH_PAGES_DIR" ]; then
          # Look for existing packages with the same version
          EXISTING_PACKAGES=$(ls -1 "$GH_PAGES_DIR/${package_name}-${package_version}-r"*.apk 2>/dev/null | sort -V || true)
          
          if [ -n "$EXISTING_PACKAGES" ]; then
            # Extract the highest release number
            for PKG_FILE in $EXISTING_PACKAGES; do
              CURRENT_RELEASE=$(echo "$PKG_FILE" | sed -n "s/.*-r\([0-9]*\)\.apk/\1/p")
              if [ -n "$CURRENT_RELEASE" ] && [ "$CURRENT_RELEASE" -ge "$release_num" ]; then
                release_num=$((CURRENT_RELEASE + 1))
              fi
            done
          fi
        fi
      done
    done
  fi
  
  # Also check what we've already built in this run
  REPO_DIR="repo/v${ALPINE_VERSION}/community/${ARCH}"
  if [ -d "$REPO_DIR" ]; then
    EXISTING_IN_RUN=$(ls -1 "$REPO_DIR/${package_name}-${package_version}-r"*.apk 2>/dev/null | sort -V || true)
    
    if [ -n "$EXISTING_IN_RUN" ]; then
      for PKG_FILE in $EXISTING_IN_RUN; do
        CURRENT_RELEASE=$(echo "$PKG_FILE" | sed -n "s/.*-r\([0-9]*\)\.apk/\1/p")
        if [ -n "$CURRENT_RELEASE" ] && [ "$CURRENT_RELEASE" -ge "$release_num" ]; then
          release_num=$((CURRENT_RELEASE + 1))
        fi
      done
    fi
  fi
  
  echo "$release_num"
}

# Create APKBUILD for each kernel variant
for variant in $VARIANTS; do
  if [ -f "${OUTPUT_DIR}/raspios-kernel-${variant}.tar.gz" ]; then
    
    # Get release number for this kernel variant
    PKG_RELEASE=$(get_release_number "raspios-kernel-${variant}" "$PKG_VERSION")
    
    echo "Creating APKBUILD for raspios-kernel-${variant} (version ${PKG_VERSION}-r${PKG_RELEASE})"
    
    # Create a proper package directory structure
    PKG_DIR="${APKBUILD_DIR}/raspios-kernel-${variant}"
    mkdir -p "$PKG_DIR"
    
    # Copy the source tarball
    cp "${OUTPUT_DIR}/raspios-kernel-${variant}.tar.gz" "$PKG_DIR/"
    
    # Determine the kernel filename suffix based on variant
    case "$variant" in
      v6)
        KERNEL_SUFFIX=""
        INITRAMFS_SUFFIX=""
        ;;
      v7)
        KERNEL_SUFFIX="7"
        INITRAMFS_SUFFIX="7"
        ;;
      v7l)
        KERNEL_SUFFIX="7l"
        INITRAMFS_SUFFIX="7l"
        ;;
      v8)
        KERNEL_SUFFIX="8"
        INITRAMFS_SUFFIX="8"
        ;;
      *)
        KERNEL_SUFFIX=""
        INITRAMFS_SUFFIX=""
        ;;
    esac
    
    # Create post-install script
    cat > "${PKG_DIR}/raspios-kernel-${variant}.post-install" << 'POST_INSTALL_HEADER'
#!/bin/sh
set -e

# Find the actual kernel version from installed modules
POST_INSTALL_HEADER
    
    cat >> "${PKG_DIR}/raspios-kernel-${variant}.post-install" << POST_INSTALL_BODY
# The full kernel version includes the variant suffix
KERNEL_BASE="${FULL_VERSION}"
KERNEL_VARIANT="${variant}"

# Find the exact kernel version from the modules directory
if [ -d /lib/modules ]; then
    # Look for module directory matching our kernel version and variant
    for moddir in /lib/modules/*; do
        if [ -d "\$moddir" ]; then
            dirname=\$(basename "\$moddir")
            # Check if this matches our kernel version pattern
            if echo "\$dirname" | grep -q "^\${KERNEL_BASE}.*-rpi-\${KERNEL_VARIANT}"; then
                KERNEL_VERSION="\$dirname"
                echo "Found kernel modules for version: \${KERNEL_VERSION}"
                break
            fi
        fi
    done
    
    # Fallback to the expected format if not found
    if [ -z "\${KERNEL_VERSION}" ]; then
        KERNEL_VERSION="\${KERNEL_BASE}-rpi-\${KERNEL_VARIANT}"
        echo "Using expected kernel version: \${KERNEL_VERSION}"
    fi
else
    KERNEL_VERSION="\${KERNEL_BASE}-rpi-\${KERNEL_VARIANT}"
    echo "No modules directory found, using: \${KERNEL_VERSION}"
fi

echo "Configuring Raspberry Pi kernel ${variant} version \${KERNEL_VERSION}..."

# Generate initramfs if mkinitfs is available
if [ -x /sbin/mkinitfs ]; then
    echo "Generating initramfs for \${KERNEL_VERSION}..."
    # Use the full kernel version for mkinitfs
    /sbin/mkinitfs -o "/boot/initramfs-\${KERNEL_VERSION}" "\${KERNEL_VERSION}" || {
        echo "Warning: mkinitfs failed, trying with base version..."
        # Fallback: try with just the base version
        /sbin/mkinitfs -o "/boot/initramfs-\${KERNEL_BASE}" "\${KERNEL_BASE}" || true
    }
    
    # Copy initramfs to firmware partition
    if [ -f "/boot/initramfs-\${KERNEL_VERSION}" ]; then
        echo "Copying initramfs to /boot/firmware/initramfs${INITRAMFS_SUFFIX}..."
        mkdir -p /boot/firmware
        cp -f "/boot/initramfs-\${KERNEL_VERSION}" "/boot/firmware/initramfs${INITRAMFS_SUFFIX}"
    elif [ -f "/boot/initramfs-\${KERNEL_BASE}" ]; then
        echo "Copying initramfs to /boot/firmware/initramfs${INITRAMFS_SUFFIX}..."
        mkdir -p /boot/firmware
        cp -f "/boot/initramfs-\${KERNEL_BASE}" "/boot/firmware/initramfs${INITRAMFS_SUFFIX}"
    fi
else
    echo "Warning: mkinitfs not found, skipping initramfs generation"
fi

# Copy kernel image to firmware partition (force overwrite)
# Try multiple possible locations for the kernel
if [ -f "/boot/vmlinuz-\${KERNEL_VERSION}" ]; then
    echo "Copying kernel to /boot/firmware/kernel${KERNEL_SUFFIX}.img..."
    mkdir -p /boot/firmware
    cp -f "/boot/vmlinuz-\${KERNEL_VERSION}" "/boot/firmware/kernel${KERNEL_SUFFIX}.img"
elif [ -f "/boot/vmlinuz-\${KERNEL_BASE}-rpi-${variant}" ]; then
    echo "Copying kernel to /boot/firmware/kernel${KERNEL_SUFFIX}.img..."
    mkdir -p /boot/firmware
    cp -f "/boot/vmlinuz-\${KERNEL_BASE}-rpi-${variant}" "/boot/firmware/kernel${KERNEL_SUFFIX}.img"
elif [ -f "/boot/vmlinuz-\${KERNEL_BASE}" ]; then
    echo "Copying kernel to /boot/firmware/kernel${KERNEL_SUFFIX}.img..."
    mkdir -p /boot/firmware
    cp -f "/boot/vmlinuz-\${KERNEL_BASE}" "/boot/firmware/kernel${KERNEL_SUFFIX}.img"
elif [ -f "/boot/vmlinuz" ]; then
    # Fallback if versioned kernel not found
    echo "Copying kernel to /boot/firmware/kernel${KERNEL_SUFFIX}.img..."
    mkdir -p /boot/firmware
    cp -f "/boot/vmlinuz" "/boot/firmware/kernel${KERNEL_SUFFIX}.img"
fi

# Copy overlays from their stored location to firmware if not already there
if [ -d "/usr/lib/linux-image-\${KERNEL_VERSION}/overlays" ] && [ ! -d "/boot/firmware/overlays" ]; then
    echo "Copying overlays to /boot/firmware/overlays..."
    mkdir -p /boot/firmware/overlays
    cp -r "/usr/lib/linux-image-\${KERNEL_VERSION}/overlays/"* "/boot/firmware/overlays/" 2>/dev/null || true
fi

echo "Raspberry Pi kernel ${variant} configuration complete."
POST_INSTALL_BODY
    
    chmod +x "${PKG_DIR}/raspios-kernel-${variant}.post-install"
    
    # Create the APKBUILD - NOTE: Using single quotes to avoid variable expansion issues
    cat > "${PKG_DIR}/APKBUILD" << 'APKBUILD_HEADER'
# Maintainer: Andy Taylor <andy@mw0mwz.co.uk>
APKBUILD_HEADER
    
    # Now append the rest with proper variable substitution
    cat >> "${PKG_DIR}/APKBUILD" << EOF
pkgname=raspios-kernel-${variant}
pkgver=${PKG_VERSION}
pkgrel=${PKG_RELEASE}
pkgdesc="Raspberry Pi OS kernel ${FULL_VERSION} for RPi ${variant}"
url="https://www.raspberrypi.org/"
arch="${ARCH}"
license="GPL-2.0"
depends="raspios-firmware mkinitfs"
makedepends=""
subpackages=""
source="raspios-kernel-${variant}.tar.gz"
install="\$pkgname.post-install"
options="!check !strip !tracedeps !fhs"

unpack() {
	cd "\$srcdir"
	tar -xzf raspios-kernel-${variant}.tar.gz
}

build() {
	# Nothing to build, just repackaging
	return 0
}

package() {
	cd "\$srcdir"
	
	# Ensure pkgdir exists
	mkdir -p "\$pkgdir"
	
	# Copy all files from the extracted directory to pkgdir
	if [ -d "raspios-kernel-${variant}" ]; then
		cd "raspios-kernel-${variant}"
		# Copy directory structure
		find . -type d -exec mkdir -p "\$pkgdir/{}" \;
		# Copy files
		find . -type f -exec cp -a {} "\$pkgdir/{}" \;
		# Copy symlinks
		find . -type l -exec cp -a {} "\$pkgdir/{}" \;
	fi
	
	# Ensure at least an empty package is created
	mkdir -p "\$pkgdir/usr/share/doc/raspios-kernel-${variant}"
	echo "Raspberry Pi OS kernel ${FULL_VERSION} for ${variant}" > "\$pkgdir/usr/share/doc/raspios-kernel-${variant}/README"
}
EOF
    
    # Generate checksums
    cd "$PKG_DIR"
    sha512sum raspios-kernel-${variant}.tar.gz > checksums
    CHECKSUM=$(cat checksums | cut -d' ' -f1)
    
    # Add checksums to APKBUILD
    echo "" >> APKBUILD
    echo "sha512sums=\"${CHECKSUM}  raspios-kernel-${variant}.tar.gz\"" >> APKBUILD
    
    cd - > /dev/null
    
    echo "Created APKBUILD for raspios-kernel-${variant} (version ${PKG_VERSION}-r${PKG_RELEASE})"
  fi
done

# Create APKBUILD for firmware (if exists)
if [ -f "${OUTPUT_DIR}/raspios-firmware.tar.gz" ]; then
  FIRMWARE_VERSION=$(date +%Y.%m.%d)
  
  # Get release number for firmware package
  PKG_RELEASE=$(get_release_number "raspios-firmware" "$FIRMWARE_VERSION")
  
  echo "Creating APKBUILD for raspios-firmware (version ${FIRMWARE_VERSION}-r${PKG_RELEASE})"
  
  # Create package directory
  PKG_DIR="${APKBUILD_DIR}/raspios-firmware"
  mkdir -p "$PKG_DIR"
  
  # Copy the source tarball
  cp "${OUTPUT_DIR}/raspios-firmware.tar.gz" "$PKG_DIR/"
  
  # Check if we have config files to include
  CONFIG_FILES=""
  if [ -f "packages/community/raspios-firmware/config.txt" ]; then
    echo "  Including config.txt"
    cp "packages/community/raspios-firmware/config.txt" "$PKG_DIR/"
    CONFIG_FILES="${CONFIG_FILES} config.txt"
  fi
  
  if [ -f "packages/community/raspios-firmware/cmdline.txt" ]; then
    echo "  Including cmdline.txt"
    cp "packages/community/raspios-firmware/cmdline.txt" "$PKG_DIR/"
    CONFIG_FILES="${CONFIG_FILES} cmdline.txt"
  fi
  
  # Create APKBUILD with proper maintainer
  cat > "${PKG_DIR}/APKBUILD" << 'APKBUILD_HEADER'
# Maintainer: Andy Taylor <andy@mw0mwz.co.uk>
APKBUILD_HEADER
  
  cat >> "${PKG_DIR}/APKBUILD" << EOF
pkgname=raspios-firmware
pkgver=${FIRMWARE_VERSION}
pkgrel=${PKG_RELEASE}
pkgdesc="Raspberry Pi firmware from Raspberry Pi OS"
url="https://www.raspberrypi.org/"
arch="${ARCH}"
license="custom"
depends=""
makedepends=""
subpackages=""
source="raspios-firmware.tar.gz${CONFIG_FILES}"
options="!check !strip !tracedeps !fhs"

unpack() {
	cd "\$srcdir"
	tar -xzf raspios-firmware.tar.gz
}

build() {
	# Nothing to build, just repackaging
	return 0
}

package() {
	cd "\$srcdir"
	
	# Ensure pkgdir exists
	mkdir -p "\$pkgdir"
	
	# Copy all files from the extracted directory to pkgdir
	if [ -d "raspios-firmware" ]; then
		cd "raspios-firmware"
		# Copy directory structure  
		find . -type d -exec mkdir -p "\$pkgdir/{}" \;
		# Copy files
		find . -type f -exec cp -a {} "\$pkgdir/{}" \;
		# Copy symlinks
		find . -type l -exec cp -a {} "\$pkgdir/{}" \;
		cd "\$srcdir"
	fi
	
	# Install config files if present
	if [ -f "\$srcdir/config.txt" ]; then
		install -Dm644 "\$srcdir/config.txt" "\$pkgdir/boot/firmware/config.txt"
	fi
	
	if [ -f "\$srcdir/cmdline.txt" ]; then
		install -Dm644 "\$srcdir/cmdline.txt" "\$pkgdir/boot/firmware/cmdline.txt"
	fi
	
	# Create symlinks in /boot pointing to /boot/firmware
	if [ -f "\$srcdir/config.txt" ] || [ -f "\$srcdir/cmdline.txt" ]; then
		mkdir -p "\$pkgdir/boot"
		cd "\$pkgdir/boot"
		
		if [ -f "\$pkgdir/boot/firmware/config.txt" ]; then
			ln -sf firmware/config.txt config.txt
		fi
		
		if [ -f "\$pkgdir/boot/firmware/cmdline.txt" ]; then
			ln -sf firmware/cmdline.txt cmdline.txt
		fi
		
		cd "\$srcdir"
	fi
	
	# Ensure at least an empty package is created
	mkdir -p "\$pkgdir/usr/share/doc/raspios-firmware"
	echo "Raspberry Pi firmware from Raspberry Pi OS" > "\$pkgdir/usr/share/doc/raspios-firmware/README"
}
EOF
  
  # Generate checksums
  cd "$PKG_DIR"
  
  # Generate checksum for the tarball
  CHECKSUM_TAR=$(sha512sum raspios-firmware.tar.gz | cut -d' ' -f1)
  
  # Generate checksums for config files if they exist
  CHECKSUMS="${CHECKSUM_TAR}  raspios-firmware.tar.gz"
  
  if [ -f "config.txt" ]; then
    CHECKSUM_CONFIG=$(sha512sum config.txt | cut -d' ' -f1)
    CHECKSUMS="${CHECKSUMS}
${CHECKSUM_CONFIG}  config.txt"
  fi
  
  if [ -f "cmdline.txt" ]; then
    CHECKSUM_CMDLINE=$(sha512sum cmdline.txt | cut -d' ' -f1)
    CHECKSUMS="${CHECKSUMS}
${CHECKSUM_CMDLINE}  cmdline.txt"
  fi
  
  # Add checksums to APKBUILD
  echo "" >> APKBUILD
  echo "sha512sums=\"${CHECKSUMS}\"" >> APKBUILD
  
  cd - > /dev/null
  
  echo "Created APKBUILD for raspios-firmware (version ${FIRMWARE_VERSION}-r${PKG_RELEASE})"
fi

# Create APKBUILD for bootloader (if exists)
if [ -f "${OUTPUT_DIR}/raspios-bootloader.tar.gz" ]; then
  BOOTLOADER_VERSION=$(date +%Y.%m.%d)
  
  # Get release number for bootloader package
  PKG_RELEASE=$(get_release_number "raspios-bootloader" "$BOOTLOADER_VERSION")
  
  echo "Creating APKBUILD for raspios-bootloader (version ${BOOTLOADER_VERSION}-r${PKG_RELEASE})"
  
  # Create package directory
  PKG_DIR="${APKBUILD_DIR}/raspios-bootloader"
  mkdir -p "$PKG_DIR"
  
  # Copy the source tarball
  cp "${OUTPUT_DIR}/raspios-bootloader.tar.gz" "$PKG_DIR/"
  
  # Create APKBUILD with proper maintainer
  cat > "${PKG_DIR}/APKBUILD" << 'APKBUILD_HEADER'
# Maintainer: Andy Taylor <andy@mw0mwz.co.uk>
APKBUILD_HEADER
  
  cat >> "${PKG_DIR}/APKBUILD" << EOF
pkgname=raspios-bootloader
pkgver=${BOOTLOADER_VERSION}
pkgrel=${PKG_RELEASE}
pkgdesc="Raspberry Pi bootloader from Raspberry Pi OS"
url="https://www.raspberrypi.org/"
arch="${ARCH}"
license="custom"
depends=""
makedepends=""
subpackages=""
source="raspios-bootloader.tar.gz"
options="!check !strip !tracedeps !fhs"

unpack() {
	cd "\$srcdir"
	tar -xzf raspios-bootloader.tar.gz
}

build() {
	# Nothing to build, just repackaging
	return 0
}

package() {
	cd "\$srcdir"
	
	# Ensure pkgdir exists
	mkdir -p "\$pkgdir"
	
	# Copy all files from the extracted directory to pkgdir
	if [ -d "raspios-bootloader" ]; then
		cd "raspios-bootloader"
		# Copy directory structure
		find . -type d -exec mkdir -p "\$pkgdir/{}" \;
		# Copy files
		find . -type f -exec cp -a {} "\$pkgdir/{}" \;
		# Copy symlinks
		find . -type l -exec cp -a {} "\$pkgdir/{}" \;
	fi
	
	# Ensure at least an empty package is created
	mkdir -p "\$pkgdir/usr/share/doc/raspios-bootloader"
	echo "Raspberry Pi bootloader from Raspberry Pi OS" > "\$pkgdir/usr/share/doc/raspios-bootloader/README"
}
EOF
  
  # Generate checksums
  cd "$PKG_DIR"
  sha512sum raspios-bootloader.tar.gz > checksums
  CHECKSUM=$(cat checksums | cut -d' ' -f1)
  
  # Add checksums to APKBUILD
  echo "" >> APKBUILD
  echo "sha512sums=\"${CHECKSUM}  raspios-bootloader.tar.gz\"" >> APKBUILD
  
  cd - > /dev/null
  
  echo "Created APKBUILD for raspios-bootloader (version ${BOOTLOADER_VERSION}-r${PKG_RELEASE})"
fi

echo "::endgroup::"