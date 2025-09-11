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

# Organize kernel packages by variant
for variant in $VARIANTS; do
  echo "Organizing files for ${variant}..."
  VARIANT_DIR="${OUTPUT_DIR}/raspios-kernel-${variant}"
  mkdir -p "$VARIANT_DIR"
  
  # Copy kernel and modules - ONLY for this specific variant
  for pkg_dir in ${EXTRACT_DIR}/linux-image-*-rpi-${variant}; do
    [ -d "$pkg_dir" ] || continue
    
    # IMPORTANT: Skip if this is actually for a different variant
    # Check the package name to ensure it's EXACTLY for this variant
    pkg_basename=$(basename "$pkg_dir")
    
    # Extract the variant from the package name
    # Pattern: linux-image-VERSION-rpi-VARIANT
    pkg_variant=$(echo "$pkg_basename" | sed -n 's/.*-rpi-\([^-]*\)$/\1/p')
    
    if [ "$pkg_variant" != "$variant" ]; then
      echo "  Skipping $pkg_basename (variant $pkg_variant != $variant)"
      continue
    fi
    
    echo "  Processing kernel/modules from $pkg_basename"
    
    # Log what module directories we're copying
    if [ -d "$pkg_dir/lib/modules" ]; then
      echo "    Module directories found:"
      for moddir in "$pkg_dir"/lib/modules/*; do
        if [ -d "$moddir" ]; then
          moddir_name=$(basename "$moddir")
          # Only copy modules that match this variant
          if echo "$moddir_name" | grep -q "rpi-${variant}$"; then
            echo "      - $moddir_name (matches variant $variant)"
          else
            echo "      - $moddir_name (skipping, doesn't match variant $variant)"
          fi
        fi
      done
    fi
    
    # Copy /lib/modules but only for this variant
    if [ -d "$pkg_dir/lib/modules" ]; then
      for moddir in "$pkg_dir"/lib/modules/*; do
        if [ -d "$moddir" ]; then
          moddir_name=$(basename "$moddir")
          # Only copy if it matches this specific variant
          if echo "$moddir_name" | grep -q "rpi-${variant}$"; then
            echo "    Copying modules: $moddir_name"
            mkdir -p "$VARIANT_DIR/lib/modules"
            cp -r "$moddir" "$VARIANT_DIR/lib/modules/"
          fi
        fi
      done
    fi
    
    # Handle /usr/lib/linux-image-* directories - ONLY for this variant
    if [ -d "$pkg_dir/usr/lib" ]; then
      for kernel_dir in "$pkg_dir"/usr/lib/linux-image-*-rpi-${variant}; do
        if [ -d "$kernel_dir" ]; then
          kernel_dir_name=$(basename "$kernel_dir")
          
          # Double-check this is for the correct variant
          if ! echo "$kernel_dir_name" | grep -q "rpi-${variant}$"; then
            echo "    Skipping $kernel_dir_name (doesn't match variant $variant)"
            continue
          fi
          
          echo "    Found kernel directory: $kernel_dir_name"
          
          # Move broadcom DTB files to /boot/firmware/
          if [ -d "$kernel_dir/broadcom" ]; then
            echo "    Relocating DTB files from $kernel_dir_name/broadcom to /boot/firmware/"
            mkdir -p "$VARIANT_DIR/boot/firmware"
            cp -r "$kernel_dir/broadcom/"* "$VARIANT_DIR/boot/firmware/" 2>/dev/null || true
          fi
          
          # SKIP overlays - they will be handled by firmware package
          if [ -d "$kernel_dir/overlays" ]; then
            echo "    Skipping overlays (will be included in firmware package)"
          fi
          
          # Copy everything else EXCEPT broadcom and overlays directories
          for item in "$kernel_dir"/*; do
            item_name=$(basename "$item")
            if [ "$item_name" != "broadcom" ] && [ "$item_name" != "overlays" ]; then
              mkdir -p "$VARIANT_DIR/usr/lib/$kernel_dir_name"
              cp -r "$item" "$VARIANT_DIR/usr/lib/$kernel_dir_name/" 2>/dev/null || true
            fi
          done
        fi
      done
    fi
    
    # Copy /boot files but only if they're variant-specific
    if [ -d "$pkg_dir/boot" ]; then
      for boot_file in "$pkg_dir"/boot/*; do
        if [ -f "$boot_file" ]; then
          boot_filename=$(basename "$boot_file")
          # Check if this boot file is variant-specific
          if echo "$boot_filename" | grep -q "rpi-${variant}"; then
            echo "    Copying boot file: $boot_filename"
            mkdir -p "$VARIANT_DIR/boot"
            cp "$boot_file" "$VARIANT_DIR/boot/"
          elif [[ "$boot_filename" == "vmlinuz"* ]] && echo "$boot_filename" | grep -q "${KERNEL_VERSION}"; then
            # Also copy versioned vmlinuz files that match our kernel version
            echo "    Copying kernel image: $boot_filename"
            mkdir -p "$VARIANT_DIR/boot"
            cp "$boot_file" "$VARIANT_DIR/boot/"
          fi
        fi
      done
    fi
    
    # Copy other top-level directories (like /usr/share/doc, etc)
    for top_dir in "$pkg_dir"/*; do
      top_dir_name=$(basename "$top_dir")
      
      # Skip directories we've already handled specially
      if [ "$top_dir_name" = "lib" ] || [ "$top_dir_name" = "usr" ] || [ "$top_dir_name" = "boot" ]; then
        continue
      fi
      
      # Check for circular symlinks before copying
      if [ -L "$top_dir" ]; then
        link_target=$(readlink "$top_dir")
        link_name=$(basename "$top_dir")
        if [ "$link_target" = "." ] || [ "$link_target" = "./" ] || [ "$link_target" = "boot" ] || [ "$link_name" = "$link_target" ]; then
          echo "    Skipping circular/self-referential symlink: $top_dir -> $link_target"
          continue
        fi
      fi
      
      if [ -d "$top_dir" ] || [ -f "$top_dir" ]; then
        cp -r "$top_dir" "$VARIANT_DIR/" 2>/dev/null || true
      fi
    done
  done
  
  # Copy variant-specific headers only
  for pkg_dir in ${EXTRACT_DIR}/linux-headers-*-rpi-${variant}; do
    [ -d "$pkg_dir" ] || continue
    
    # Skip common headers packages
    if [[ "$(basename $pkg_dir)" =~ "common" ]]; then
      continue
    fi
    
    # Double-check this is for the correct variant
    pkg_basename=$(basename "$pkg_dir")
    pkg_variant=$(echo "$pkg_basename" | sed -n 's/.*-rpi-\([^-]*\)$/\1/p')
    
    if [ "$pkg_variant" != "$variant" ]; then
      echo "  Skipping headers $pkg_basename (variant $pkg_variant != $variant)"
      continue
    fi
    
    echo "  Copying variant-specific headers from $pkg_basename"
    cp -r "$pkg_dir"/* "$VARIANT_DIR/" 2>/dev/null || true
  done
  
  # Final cleanup: ensure no circular /boot/boot symlink exists
  if [ -L "$VARIANT_DIR/boot/boot" ]; then
    echo "  Final cleanup: removing /boot/boot circular symlink"
    rm -f "$VARIANT_DIR/boot/boot"
  fi
  
  # IMPORTANT: Remove any overlays that might have been copied to kernel package
  if [ -d "$VARIANT_DIR/boot/firmware/overlays" ]; then
    echo "  Removing overlays from kernel package (belong in firmware)"
    rm -rf "$VARIANT_DIR/boot/firmware/overlays"
  fi
  
  # Final verification: ensure we only have files for this variant
  echo "  Verifying package contains only ${variant} files:"
  if [ -d "$VARIANT_DIR/usr/lib" ]; then
    for kernel_dir in "$VARIANT_DIR"/usr/lib/linux-image-*; do
      if [ -d "$kernel_dir" ]; then
        kernel_dir_name=$(basename "$kernel_dir")
        if echo "$kernel_dir_name" | grep -q "rpi-${variant}$"; then
          echo "    ✓ $kernel_dir_name (correct)"
        else
          echo "    ✗ $kernel_dir_name (WRONG - removing)"
          rm -rf "$kernel_dir"
        fi
      fi
    done
  fi
  
  if [ -d "$VARIANT_DIR/lib/modules" ]; then
    for moddir in "$VARIANT_DIR"/lib/modules/*; do
      if [ -d "$moddir" ]; then
        moddir_name=$(basename "$moddir")
        if echo "$moddir_name" | grep -q "rpi-${variant}$"; then
          echo "    ✓ modules/$moddir_name (correct)"
        else
          echo "    ✗ modules/$moddir_name (WRONG - removing)"
          rm -rf "$moddir"
        fi
      fi
    done
  fi
  
  # Create tarball if files exist
  if [ -d "$VARIANT_DIR/boot" ] || [ -d "$VARIANT_DIR/lib" ] || [ -d "$VARIANT_DIR/usr" ]; then
    echo "Creating tarball for ${variant}..."
    tar czf "${OUTPUT_DIR}/raspios-kernel-${variant}.tar.gz" -C "$OUTPUT_DIR" "raspios-kernel-${variant}"
    
    # Show what's in the package for verification
    if [ -d "$VARIANT_DIR/boot/firmware" ]; then
      echo "  Contents of /boot/firmware for ${variant}:"
      echo "    DTB files: $(find "$VARIANT_DIR/boot/firmware" -maxdepth 1 -name "*.dtb" 2>/dev/null | wc -l)"
      echo "    Overlay files: $(find "$VARIANT_DIR/boot/firmware/overlays" -name "*.dtbo" 2>/dev/null | wc -l || echo 0) (should be 0)"
    fi
    
    if [ -d "$VARIANT_DIR/usr/lib" ]; then
      echo "  Kernel directories in /usr/lib:"
      for kdir in "$VARIANT_DIR"/usr/lib/linux-image-*; do
        [ -d "$kdir" ] && echo "    - $(basename "$kdir")"
      done
    fi
  else
    echo "  Warning: No kernel files found for ${variant}"
  fi
done

# Process common headers separately
echo "Processing common kernel headers..."
COMMON_HEADERS_DIR="${OUTPUT_DIR}/raspios-kernel-headers-common"
mkdir -p "$COMMON_HEADERS_DIR"

for pkg_dir in ${EXTRACT_DIR}/linux-headers-*-common-rpi*; do
  [ -d "$pkg_dir" ] || continue
  echo "  Copying common headers from $(basename $pkg_dir)"
  cp -r "$pkg_dir"/* "$COMMON_HEADERS_DIR/" 2>/dev/null || true
done

if [ -n "$(ls -A $COMMON_HEADERS_DIR 2>/dev/null)" ]; then
  echo "Creating common headers tarball..."
  tar czf "${OUTPUT_DIR}/raspios-kernel-headers-common.tar.gz" -C "$OUTPUT_DIR" "raspios-kernel-headers-common"
fi

# Only process firmware if we actually downloaded any firmware packages
FIRMWARE_FOUND=false
for pkg_dir in ${EXTRACT_DIR}/raspi-firmware* ${EXTRACT_DIR}/raspberrypi-firmware* ${EXTRACT_DIR}/firmware-*; do
  if [ -d "$pkg_dir" ]; then
    FIRMWARE_FOUND=true
    break
  fi
done

if [ "$FIRMWARE_FOUND" = true ]; then
  echo "Processing firmware packages..."
  FIRMWARE_DIR="${OUTPUT_DIR}/raspios-firmware"
  mkdir -p "$FIRMWARE_DIR"
  
  for pkg_dir in ${EXTRACT_DIR}/raspi-firmware* ${EXTRACT_DIR}/raspberrypi-firmware* ${EXTRACT_DIR}/firmware-*; do
    if [ -d "$pkg_dir" ]; then
      echo "  Copying firmware from $(basename $pkg_dir)"
      
      # Check if this package has firmware in /usr/lib/raspi-firmware
      if [ -d "$pkg_dir/usr/lib/raspi-firmware" ]; then
        echo "  Relocating /usr/lib/raspi-firmware to /boot/firmware"
        mkdir -p "$FIRMWARE_DIR/boot/firmware"
        cp -r "$pkg_dir/usr/lib/raspi-firmware/"* "$FIRMWARE_DIR/boot/firmware/" 2>/dev/null || true
        
        # Copy any other files that aren't in /usr/lib/raspi-firmware
        for item in "$pkg_dir"/*; do
          if [ "$(basename "$item")" != "usr" ]; then
            cp -r "$item" "$FIRMWARE_DIR/" 2>/dev/null || true
          elif [ -d "$item" ]; then
            # For /usr, copy everything except /usr/lib/raspi-firmware
            for usr_item in "$item"/*; do
              if [ "$(basename "$usr_item")" != "lib" ]; then
                mkdir -p "$FIRMWARE_DIR/usr"
                cp -r "$usr_item" "$FIRMWARE_DIR/usr/" 2>/dev/null || true
              elif [ -d "$usr_item" ]; then
                # For /usr/lib, copy everything except raspi-firmware
                for lib_item in "$usr_item"/*; do
                  if [ "$(basename "$lib_item")" != "raspi-firmware" ]; then
                    mkdir -p "$FIRMWARE_DIR/usr/lib"
                    cp -r "$lib_item" "$FIRMWARE_DIR/usr/lib/" 2>/dev/null || true
                  fi
                done
              fi
            done
          fi
        done
      else
        # No /usr/lib/raspi-firmware, just copy everything as-is
        cp -r "$pkg_dir"/* "$FIRMWARE_DIR/" 2>/dev/null || true
      fi
    fi
  done
  
  # Collect ALL overlays from ALL kernel packages and put them in firmware
  echo "Collecting overlays for firmware package from all kernel variants..."
  mkdir -p "$FIRMWARE_DIR/boot/firmware/overlays"
  
  # Collect from extracted packages
  for pkg_dir in ${EXTRACT_DIR}/linux-image-*; do
    if [ -d "$pkg_dir" ]; then
      # Look for overlays in /usr/lib/linux-image-*/overlays
      for kernel_dir in "$pkg_dir"/usr/lib/linux-image-*/overlays; do
        if [ -d "$kernel_dir" ]; then
          echo "  Adding overlays from $(basename $(dirname "$kernel_dir"))"
          cp -r "$kernel_dir"/* "$FIRMWARE_DIR/boot/firmware/overlays/" 2>/dev/null || true
        fi
      done
      
      # Also check if overlays are directly in /boot/firmware/overlays in the package
      if [ -d "$pkg_dir/boot/firmware/overlays" ]; then
        echo "  Adding overlays from $(basename "$pkg_dir") /boot/firmware/overlays"
        cp -r "$pkg_dir/boot/firmware/overlays"/* "$FIRMWARE_DIR/boot/firmware/overlays/" 2>/dev/null || true
      fi
    fi
  done
  
  # Remove duplicates - overlays should be the same across all kernel versions
  if [ -d "$FIRMWARE_DIR/boot/firmware/overlays" ]; then
    overlay_count=$(find "$FIRMWARE_DIR/boot/firmware/overlays" -name "*.dtbo" 2>/dev/null | wc -l)
    echo "  Total overlay files collected in firmware package: $overlay_count"
  fi
  
  if [ -n "$(ls -A $FIRMWARE_DIR 2>/dev/null)" ]; then
    echo "Creating firmware tarball..."
    tar czf "${OUTPUT_DIR}/raspios-firmware.tar.gz" -C "$OUTPUT_DIR" "raspios-firmware"
  fi
else
  echo "No firmware packages found to process"
fi

echo ""
echo "Extraction complete. Created tarballs:"
ls -lh "${OUTPUT_DIR}"/*.tar.gz 2>/dev/null || echo "No tarballs created"

echo "::endgroup::"