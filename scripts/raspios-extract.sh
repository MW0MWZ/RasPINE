#!/bin/bash
# scripts/raspios-extract.sh
# Extract and organize Raspberry Pi OS packages

set -e

echo "::group::Extracting Debian packages"

WORK_DIR="raspios-work"
EXTRACT_DIR="${WORK_DIR}/extracted"
OUTPUT_DIR="raspios-apk-staging"

mkdir -p "$EXTRACT_DIR" "$OUTPUT_DIR"

# Extract all .deb files
for deb in ${WORK_DIR}/debs/*.deb; do
  [ -f "$deb" ] || continue
  basename=$(basename "$deb" .deb)
  echo "Extracting $basename..."
  dpkg-deb -x "$deb" "$EXTRACT_DIR/$basename"
done

# First, collect ALL DTBs and overlays for the firmware package
# We do this BEFORE processing kernel packages
echo "Collecting all DTBs and overlays for firmware package..."
FIRMWARE_DIR="${OUTPUT_DIR}/raspios-firmware"
mkdir -p "$FIRMWARE_DIR/boot/firmware/overlays"

# Collect DTBs from ALL kernel packages
echo "  Scanning all packages for DTB files..."
for pkg_dir in ${EXTRACT_DIR}/*; do
  [ -d "$pkg_dir" ] || continue
  pkg_name=$(basename "$pkg_dir")
  
  if echo "$pkg_name" | grep -q "^linux-image-"; then
    echo "    Checking $pkg_name for DTBs..."
    
    # Find ALL .dtb files anywhere in this package
    find "$pkg_dir" -name "*.dtb" -type f 2>/dev/null | while read dtb_file; do
      dtb_name=$(basename "$dtb_file")
      # Only copy if not already present (first one wins)
      if [ ! -f "$FIRMWARE_DIR/boot/firmware/$dtb_name" ]; then
        cp "$dtb_file" "$FIRMWARE_DIR/boot/firmware/" 2>/dev/null || true
        echo "      Added DTB: $dtb_name"
      fi
    done
    
    # Find ALL overlay files (.dtbo) anywhere in this package
    find "$pkg_dir" -name "*.dtbo" -type f 2>/dev/null | while read overlay_file; do
      overlay_name=$(basename "$overlay_file")
      # Only copy if not already present (first one wins)
      if [ ! -f "$FIRMWARE_DIR/boot/firmware/overlays/$overlay_name" ]; then
        cp "$overlay_file" "$FIRMWARE_DIR/boot/firmware/overlays/" 2>/dev/null || true
        echo "      Added overlay: $overlay_name"
      fi
    done
    
    # Also look for README files in overlay directories
    find "$pkg_dir" -path "*/overlays/README" -type f 2>/dev/null | while read readme_file; do
      if [ ! -f "$FIRMWARE_DIR/boot/firmware/overlays/README" ]; then
        cp "$readme_file" "$FIRMWARE_DIR/boot/firmware/overlays/" 2>/dev/null || true
        echo "      Added overlays README"
      fi
    done
  fi
done

# Count what we collected
DTB_COUNT=$(find "$FIRMWARE_DIR/boot/firmware" -maxdepth 1 -name "*.dtb" 2>/dev/null | wc -l)
OVERLAY_COUNT=$(find "$FIRMWARE_DIR/boot/firmware/overlays" -name "*.dtbo" 2>/dev/null | wc -l)
echo "  Collected $DTB_COUNT DTB files and $OVERLAY_COUNT overlay files"

# List the bcm2708/bcm2709 DTBs specifically to verify they're included
echo "  Verifying critical DTBs:"
for pattern in "bcm2708-*.dtb" "bcm2709-*.dtb" "bcm2710-*.dtb" "bcm2711-*.dtb"; do
  count=$(find "$FIRMWARE_DIR/boot/firmware" -maxdepth 1 -name "$pattern" 2>/dev/null | wc -l)
  if [ $count -gt 0 ]; then
    echo "    ✓ Found $count $pattern files"
  else
    echo "    ⚠ No $pattern files found"
  fi
done

# Now process kernel packages - ONLY copy what we explicitly want
for variant in $VARIANTS; do
  echo "Organizing kernel files for ${variant}..."
  VARIANT_DIR="${OUTPUT_DIR}/raspios-kernel-${variant}"
  mkdir -p "$VARIANT_DIR"
  
  # Process each extracted directory
  found_kernel=false
  for pkg_dir in ${EXTRACT_DIR}/*; do
    [ -d "$pkg_dir" ] || continue
    
    pkg_name=$(basename "$pkg_dir")
    
    # Check if this is a kernel image package for our variant
    if echo "$pkg_name" | grep -q "^linux-image-.*-rpi-${variant}\(_\|$\)"; then
      echo "  Processing kernel package: $pkg_name"
      found_kernel=true
      
      # ONLY copy specific things we want for kernel packages:
      
      # 1. Copy kernel images from /boot (but not DTBs)
      if [ -d "$pkg_dir/boot" ]; then
        echo "    Copying kernel images from /boot..."
        mkdir -p "$VARIANT_DIR/boot"
        
        # Only copy specific kernel-related files
        for file in "$pkg_dir/boot"/*; do
          [ -f "$file" ] || continue
          filename=$(basename "$file")
          
          # Only copy kernel images, System.map, config files
          # Skip .dtb files and anything else
          case "$filename" in
            kernel*.img|vmlinuz*|System.map*|config-*)
              cp "$file" "$VARIANT_DIR/boot/" 2>/dev/null || true
              echo "      Copied: $filename"
              ;;
            *.dtb)
              echo "      Skipped DTB: $filename (goes in firmware package)"
              ;;
          esac
        done
      fi
      
      # 2. Copy kernel images from /boot/firmware if present (but not DTBs)
      if [ -d "$pkg_dir/boot/firmware" ]; then
        echo "    Copying kernel images from /boot/firmware..."
        mkdir -p "$VARIANT_DIR/boot/firmware"
        
        for file in "$pkg_dir/boot/firmware"/*; do
          [ -f "$file" ] || continue
          filename=$(basename "$file")
          
          # Only copy kernel images, skip DTBs
          case "$filename" in
            kernel*.img|vmlinuz*)
              cp "$file" "$VARIANT_DIR/boot/firmware/" 2>/dev/null || true
              echo "      Copied: $filename"
              ;;
            *.dtb)
              echo "      Skipped DTB: $filename (goes in firmware package)"
              ;;
          esac
        done
      fi
      
      # 3. Copy kernel modules - these are always needed
      if [ -d "$pkg_dir/lib/modules" ]; then
        echo "    Copying kernel modules..."
        mkdir -p "$VARIANT_DIR/lib"
        cp -r "$pkg_dir/lib/modules" "$VARIANT_DIR/lib/" 2>/dev/null || true
        module_count=$(find "$VARIANT_DIR/lib/modules" -name "*.ko" 2>/dev/null | wc -l)
        echo "      Copied $module_count kernel modules"
      fi
      
      # 4. DO NOT COPY /usr/lib/linux-image-* directories at all
      # These contain DTBs and overlays that belong in firmware package
      echo "    Skipping /usr/lib/linux-image-* directories (DTBs/overlays go in firmware package)"
      
      # 5. Copy other /usr files but explicitly exclude linux-image-* directories
      if [ -d "$pkg_dir/usr" ]; then
        echo "    Copying other /usr files..."
        
        # Copy /usr/share if it exists (documentation, etc)
        if [ -d "$pkg_dir/usr/share" ]; then
          mkdir -p "$VARIANT_DIR/usr"
          cp -r "$pkg_dir/usr/share" "$VARIANT_DIR/usr/" 2>/dev/null || true
        fi
        
        # Copy /usr/bin if it exists
        if [ -d "$pkg_dir/usr/bin" ]; then
          mkdir -p "$VARIANT_DIR/usr"
          cp -r "$pkg_dir/usr/bin" "$VARIANT_DIR/usr/" 2>/dev/null || true
        fi
        
        # Copy /usr/sbin if it exists
        if [ -d "$pkg_dir/usr/sbin" ]; then
          mkdir -p "$VARIANT_DIR/usr"
          cp -r "$pkg_dir/usr/sbin" "$VARIANT_DIR/usr/" 2>/dev/null || true
        fi
        
        # For /usr/lib, be very selective - skip linux-image-* completely
        if [ -d "$pkg_dir/usr/lib" ]; then
          for libdir in "$pkg_dir/usr/lib"/*; do
            [ -e "$libdir" ] || continue
            libname=$(basename "$libdir")
            
            # Skip any linux-image-* directories completely
            if echo "$libname" | grep -q "^linux-image-"; then
              echo "      Skipping /usr/lib/$libname (contains DTBs/overlays)"
            else
              # Copy other lib directories
              mkdir -p "$VARIANT_DIR/usr/lib"
              cp -r "$libdir" "$VARIANT_DIR/usr/lib/" 2>/dev/null || true
            fi
          done
        fi
      fi
    fi
    
    # Check if this is a headers package for our variant
    if echo "$pkg_name" | grep -q "^linux-headers-.*-rpi-${variant}\(_\|$\)"; then
      # Skip common headers (processed separately)
      if ! echo "$pkg_name" | grep -q "common"; then
        echo "  Processing headers package: $pkg_name"
        
        # Headers can be copied as-is, they don't have DTBs
        cp -r "$pkg_dir"/* "$VARIANT_DIR/" 2>/dev/null || true
      fi
    fi
  done
  
  # Special handling for v8 on arm64 - packages might not have -v8 suffix
  if [ "$variant" = "v8" ] && [ "$ARCH" = "aarch64" ] && [ "$found_kernel" = "false" ]; then
    echo "  No -v8 packages found, checking for arm64 packages without variant suffix..."
    
    for pkg_dir in ${EXTRACT_DIR}/*; do
      [ -d "$pkg_dir" ] || continue
      
      pkg_name=$(basename "$pkg_dir")
      
      # Look for linux-image packages that end with -rpi_ (no variant)
      if echo "$pkg_name" | grep -q "^linux-image-.*-rpi_"; then
        # Make sure it's not for a different variant
        if ! echo "$pkg_name" | grep -q "rpi-v[67]"; then
          echo "  Processing arm64 kernel package: $pkg_name"
          found_kernel=true
          
          # Copy only kernel images and modules (same selective approach as above)
          if [ -d "$pkg_dir/boot" ]; then
            mkdir -p "$VARIANT_DIR/boot"
            for file in "$pkg_dir/boot"/*; do
              [ -f "$file" ] || continue
              filename=$(basename "$file")
              case "$filename" in
                kernel*.img|vmlinuz*|System.map*|config-*)
                  cp "$file" "$VARIANT_DIR/boot/" 2>/dev/null || true
                  ;;
              esac
            done
          fi
          
          if [ -d "$pkg_dir/boot/firmware" ]; then
            mkdir -p "$VARIANT_DIR/boot/firmware"
            for file in "$pkg_dir/boot/firmware"/*; do
              [ -f "$file" ] || continue
              filename=$(basename "$file")
              case "$filename" in
                kernel*.img|vmlinuz*)
                  cp "$file" "$VARIANT_DIR/boot/firmware/" 2>/dev/null || true
                  ;;
              esac
            done
          fi
          
          if [ -d "$pkg_dir/lib/modules" ]; then
            mkdir -p "$VARIANT_DIR/lib"
            cp -r "$pkg_dir/lib/modules" "$VARIANT_DIR/lib/" 2>/dev/null || true
          fi
        fi
      fi
      
      # Same for headers
      if echo "$pkg_name" | grep -q "^linux-headers-.*-rpi_"; then
        if ! echo "$pkg_name" | grep -q "rpi-v[67]\|common"; then
          echo "  Processing arm64 headers package: $pkg_name"
          cp -r "$pkg_dir"/* "$VARIANT_DIR/" 2>/dev/null || true
        fi
      fi
    done
  fi
  
  # Final verification and create tarball
  echo "  Verifying package contents for ${variant}:"
  
  has_content=false
  if [ -d "$VARIANT_DIR/boot" ] && [ -n "$(ls -A "$VARIANT_DIR/boot" 2>/dev/null)" ]; then
    kernel_count=$(find "$VARIANT_DIR/boot" -name "kernel*.img" -o -name "vmlinuz-*" 2>/dev/null | wc -l)
    echo "    ✓ /boot: $kernel_count kernel images"
    has_content=true
  fi
  if [ -d "$VARIANT_DIR/lib/modules" ] && [ -n "$(ls -A "$VARIANT_DIR/lib/modules" 2>/dev/null)" ]; then
    echo "    ✓ /lib/modules: $(ls "$VARIANT_DIR/lib/modules" | wc -l) module directories"
    has_content=true
  fi
  if [ -d "$VARIANT_DIR/usr" ] && [ -n "$(find "$VARIANT_DIR/usr" -type f 2>/dev/null)" ]; then
    echo "    ✓ /usr: present with files"
    has_content=true
  fi
  
  # Verify NO DTBs are in kernel package
  dtb_check=$(find "$VARIANT_DIR" -name "*.dtb" 2>/dev/null | wc -l)
  if [ $dtb_check -gt 0 ]; then
    echo "    ⚠️ WARNING: Found $dtb_check DTB files that shouldn't be in kernel package!"
    find "$VARIANT_DIR" -name "*.dtb" | head -5
  else
    echo "    ✓ No DTB files (correct - they're in firmware package)"
  fi
  
  # Verify NO /usr/lib/linux-image-* directories
  if [ -d "$VARIANT_DIR/usr/lib" ]; then
    linux_image_dirs=$(find "$VARIANT_DIR/usr/lib" -type d -name "linux-image-*" 2>/dev/null | wc -l)
    if [ $linux_image_dirs -gt 0 ]; then
      echo "    ⚠️ WARNING: Found linux-image directories that shouldn't be here!"
      find "$VARIANT_DIR/usr/lib" -type d -name "linux-image-*"
    else
      echo "    ✓ No /usr/lib/linux-image-* directories (correct)"
    fi
  fi
  
  # Create tarball if we have content
  if [ "$has_content" = "true" ]; then
    echo "  Creating tarball for ${variant}..."
    tar czf "${OUTPUT_DIR}/raspios-kernel-${variant}.tar.gz" -C "$OUTPUT_DIR" "raspios-kernel-${variant}"
    echo "  ✓ Created raspios-kernel-${variant}.tar.gz"
  else
    echo "  ⚠️ Warning: No kernel files found for ${variant}"
  fi
done

# Process common headers separately
echo "Processing common kernel headers..."
COMMON_HEADERS_DIR="${OUTPUT_DIR}/raspios-kernel-headers-common"
mkdir -p "$COMMON_HEADERS_DIR"

for pkg_dir in ${EXTRACT_DIR}/*; do
  [ -d "$pkg_dir" ] || continue
  pkg_name=$(basename "$pkg_dir")
  
  if echo "$pkg_name" | grep -q "^linux-headers-.*-common-rpi"; then
    echo "  Copying common headers from $pkg_name"
    cp -r "$pkg_dir"/* "$COMMON_HEADERS_DIR/" 2>/dev/null || true
  fi
done

if [ -n "$(ls -A $COMMON_HEADERS_DIR 2>/dev/null)" ]; then
  echo "Creating common headers tarball..."
  tar czf "${OUTPUT_DIR}/raspios-kernel-headers-common.tar.gz" -C "$OUTPUT_DIR" "raspios-kernel-headers-common"
fi

# Process firmware packages (now includes ALL DTBs and overlays we collected earlier)
FIRMWARE_FOUND=false
for pkg_dir in ${EXTRACT_DIR}/*; do
  [ -d "$pkg_dir" ] || continue
  pkg_name=$(basename "$pkg_dir")
  
  if echo "$pkg_name" | grep -q "^raspi-firmware\|^raspberrypi-firmware\|^firmware-"; then
    FIRMWARE_FOUND=true
    break
  fi
done

if [ "$FIRMWARE_FOUND" = "true" ]; then
  echo "Processing firmware packages..."
  
  for pkg_dir in ${EXTRACT_DIR}/*; do
    [ -d "$pkg_dir" ] || continue
    pkg_name=$(basename "$pkg_dir")
    
    if echo "$pkg_name" | grep -q "^raspi-firmware\|^raspberrypi-firmware\|^firmware-"; then
      echo "  Copying firmware from $pkg_name"
      
      if [ -d "$pkg_dir/usr/lib/raspi-firmware" ]; then
        echo "    Relocating /usr/lib/raspi-firmware to /boot/firmware"
        mkdir -p "$FIRMWARE_DIR/boot/firmware"
        
        # Copy everything EXCEPT .dtb files and overlays (we already have all of those)
        for item in "$pkg_dir/usr/lib/raspi-firmware"/*; do
          [ -e "$item" ] || continue
          item_name=$(basename "$item")
          
          # Skip DTBs and overlays directory (we already collected these)
          case "$item_name" in
            *.dtb)
              echo "      Skipping $item_name (already collected)"
              ;;
            overlays)
              echo "      Skipping overlays directory (already collected)"
              ;;
            *)
              cp -r "$item" "$FIRMWARE_DIR/boot/firmware/" 2>/dev/null || true
              echo "      Copied: $item_name"
              ;;
          esac
        done
        
        # Copy other files (not in /usr/lib/raspi-firmware)
        for item in "$pkg_dir"/*; do
          if [ "$(basename "$item")" != "usr" ]; then
            cp -r "$item" "$FIRMWARE_DIR/" 2>/dev/null || true
          fi
        done
      else
        # No relocation needed, copy selectively
        cp -r "$pkg_dir/lib" "$FIRMWARE_DIR/" 2>/dev/null || true
        cp -r "$pkg_dir/etc" "$FIRMWARE_DIR/" 2>/dev/null || true
        cp -r "$pkg_dir/opt" "$FIRMWARE_DIR/" 2>/dev/null || true
        
        # For /boot, be selective to avoid overwriting our collected DTBs
        if [ -d "$pkg_dir/boot" ]; then
          # Copy boot files but not DTBs or overlays
          for item in "$pkg_dir/boot"/*; do
            [ -e "$item" ] || continue
            item_name=$(basename "$item")
            
            if [ "$item_name" = "firmware" ]; then
              # Handle /boot/firmware specially
              if [ -d "$item" ]; then
                mkdir -p "$FIRMWARE_DIR/boot/firmware"
                for fwitem in "$item"/*; do
                  [ -e "$fwitem" ] || continue
                  fwitem_name=$(basename "$fwitem")
                  
                  case "$fwitem_name" in
                    *.dtb|overlays)
                      # Skip, we already have these
                      ;;
                    *)
                      cp -r "$fwitem" "$FIRMWARE_DIR/boot/firmware/" 2>/dev/null || true
                      ;;
                  esac
                done
              fi
            else
              # Not firmware subdirectory
              case "$item_name" in
                *.dtb)
                  # Skip DTBs
                  ;;
                *)
                  mkdir -p "$FIRMWARE_DIR/boot"
                  cp -r "$item" "$FIRMWARE_DIR/boot/" 2>/dev/null || true
                  ;;
              esac
            fi
          done
        fi
      fi
    fi
  done
  
  # Create symlink for Cypress WiFi firmware compatibility
  echo "Creating Cypress WiFi firmware symlinks..."
  if [ -d "$FIRMWARE_DIR/lib/firmware/cypress" ]; then
    cd "$FIRMWARE_DIR/lib/firmware/cypress"
    
    # Create symlink for cyfmac43455-sdio.bin if the standard version exists
    if [ -f "cyfmac43455-sdio-standard.bin" ] && [ ! -e "cyfmac43455-sdio.bin" ]; then
      ln -sf cyfmac43455-sdio-standard.bin cyfmac43455-sdio.bin
      echo "  Created symlink: cyfmac43455-sdio.bin -> cyfmac43455-sdio-standard.bin"
    fi
    
    # Add other common Cypress symlinks if needed
    # For BCM43430 (Pi Zero W, Pi 3B)
    if [ -f "cyfmac43430-sdio-raspberrypi,model-zero-w.bin" ] && [ ! -e "cyfmac43430-sdio.bin" ]; then
      ln -sf "cyfmac43430-sdio-raspberrypi,model-zero-w.bin" cyfmac43430-sdio.bin
      echo "  Created symlink: cyfmac43430-sdio.bin -> cyfmac43430-sdio-raspberrypi,model-zero-w.bin"
    fi
    
    cd - > /dev/null
  fi
  
  # Final verification of firmware package
  echo "Verifying firmware package contents:"
  echo "  DTB files: $(find "$FIRMWARE_DIR/boot/firmware" -maxdepth 1 -name "*.dtb" 2>/dev/null | wc -l)"
  echo "  Overlay files: $(find "$FIRMWARE_DIR/boot/firmware/overlays" -name "*.dtbo" 2>/dev/null | wc -l)"
  echo "  Bootloader files: $(find "$FIRMWARE_DIR/boot/firmware" -maxdepth 1 \( -name "*.elf" -o -name "*.dat" \) 2>/dev/null | wc -l)"
  
  # List specific critical DTBs to ensure they're present
  echo "  Critical DTBs check:"
  for dtb in bcm2708-rpi-b.dtb bcm2708-rpi-zero.dtb bcm2709-rpi-2-b.dtb bcm2710-rpi-3-b.dtb bcm2711-rpi-4-b.dtb; do
    if [ -f "$FIRMWARE_DIR/boot/firmware/$dtb" ]; then
      echo "    ✓ $dtb"
    else
      echo "    ✗ $dtb MISSING!"
    fi
  done
  
  if [ -n "$(ls -A $FIRMWARE_DIR 2>/dev/null)" ]; then
    echo "Creating firmware tarball..."
    tar czf "${OUTPUT_DIR}/raspios-firmware.tar.gz" -C "$OUTPUT_DIR" "raspios-firmware"
  fi
fi

echo ""
echo "Extraction complete. Created tarballs:"
ls -lh "${OUTPUT_DIR}"/*.tar.gz 2>/dev/null || echo "No tarballs created"

echo "::endgroup::"