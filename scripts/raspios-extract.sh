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
  
  # Copy kernel and modules
  for pkg_dir in ${EXTRACT_DIR}/linux-image-*-rpi-${variant}*; do
    [ -d "$pkg_dir" ] || continue
    echo "  Processing kernel/modules from $(basename $pkg_dir)"
    
    # First, handle DTB files and overlays relocation
    if [ -d "$pkg_dir/usr/lib" ]; then
      for kernel_dir in "$pkg_dir"/usr/lib/linux-image-*-rpi-${variant}*; do
        if [ -d "$kernel_dir" ]; then
          KERNEL_VERSION_DIR=$(basename "$kernel_dir")
          echo "    Found kernel directory: $KERNEL_VERSION_DIR"
          
          # Move broadcom DTB files to /boot/firmware/
          if [ -d "$kernel_dir/broadcom" ]; then
            echo "    Relocating DTB files from $KERNEL_VERSION_DIR/broadcom to /boot/firmware/"
            mkdir -p "$VARIANT_DIR/boot/firmware"
            cp -r "$kernel_dir/broadcom/"* "$VARIANT_DIR/boot/firmware/" 2>/dev/null || true
          fi
          
          # Move overlays to /boot/firmware/overlays
          if [ -d "$kernel_dir/overlays" ]; then
            echo "    Relocating overlays from $KERNEL_VERSION_DIR/overlays to /boot/firmware/overlays"
            mkdir -p "$VARIANT_DIR/boot/firmware/overlays"
            cp -r "$kernel_dir/overlays/"* "$VARIANT_DIR/boot/firmware/overlays/" 2>/dev/null || true
          fi
          
          # Now copy everything else EXCEPT the broadcom and overlays directories
          for item in "$kernel_dir"/*; do
            item_name=$(basename "$item")
            if [ "$item_name" != "broadcom" ] && [ "$item_name" != "overlays" ]; then
              # This preserves other files that might be in the kernel directory
              mkdir -p "$VARIANT_DIR/usr/lib/$KERNEL_VERSION_DIR"
              cp -r "$item" "$VARIANT_DIR/usr/lib/$KERNEL_VERSION_DIR/" 2>/dev/null || true
            fi
          done
        fi
      done
    fi
    
    # Copy all other files from the package (preserving directory structure)
    # but skip /usr/lib/linux-image-* since we handled it specially above
    for top_dir in "$pkg_dir"/*; do
      if [ -d "$top_dir" ]; then
        top_dir_name=$(basename "$top_dir")
        if [ "$top_dir_name" = "usr" ]; then
          # Handle /usr specially
          for usr_subdir in "$top_dir"/*; do
            if [ -d "$usr_subdir" ]; then
              usr_subdir_name=$(basename "$usr_subdir")
              if [ "$usr_subdir_name" = "lib" ]; then
                # Handle /usr/lib specially
                for lib_item in "$usr_subdir"/*; do
                  lib_item_name=$(basename "$lib_item")
                  # Skip linux-image-* directories as we handled them above
                  if [[ ! "$lib_item_name" =~ ^linux-image- ]]; then
                    mkdir -p "$VARIANT_DIR/usr/lib"
                    cp -r "$lib_item" "$VARIANT_DIR/usr/lib/" 2>/dev/null || true
                  fi
                done
              else
                # Copy other /usr subdirectories normally
                mkdir -p "$VARIANT_DIR/usr"
                cp -r "$usr_subdir" "$VARIANT_DIR/usr/" 2>/dev/null || true
              fi
            elif [ -f "$usr_subdir" ]; then
              mkdir -p "$VARIANT_DIR/usr"
              cp "$usr_subdir" "$VARIANT_DIR/usr/" 2>/dev/null || true
            fi
          done
        else
          # Copy other top-level directories normally
          cp -r "$top_dir" "$VARIANT_DIR/" 2>/dev/null || true
        fi
      elif [ -f "$top_dir" ]; then
        cp "$top_dir" "$VARIANT_DIR/" 2>/dev/null || true
      fi
    done
  done
  
  # Copy variant-specific headers only
  for pkg_dir in ${EXTRACT_DIR}/linux-headers-*-rpi-${variant}*; do
    [ -d "$pkg_dir" ] || continue
    # Skip common headers packages
    if [[ "$(basename $pkg_dir)" =~ "common" ]]; then
      continue
    fi
    echo "  Copying variant-specific headers from $(basename $pkg_dir)"
    cp -r "$pkg_dir"/* "$VARIANT_DIR/" 2>/dev/null || true
  done
  
  # Create tarball if files exist
  if [ -d "$VARIANT_DIR/boot" ] || [ -d "$VARIANT_DIR/lib" ] || [ -d "$VARIANT_DIR/usr" ]; then
    echo "Creating tarball for ${variant}..."
    tar czf "${OUTPUT_DIR}/raspios-kernel-${variant}.tar.gz" -C "$OUTPUT_DIR" "raspios-kernel-${variant}"
    
    # Show what's in /boot/firmware for verification
    if [ -d "$VARIANT_DIR/boot/firmware" ]; then
      echo "  Contents of /boot/firmware for ${variant}:"
      echo "    DTB files: $(find "$VARIANT_DIR/boot/firmware" -maxdepth 1 -name "*.dtb" 2>/dev/null | wc -l)"
      echo "    Overlay files: $(find "$VARIANT_DIR/boot/firmware/overlays" -name "*.dtbo" 2>/dev/null | wc -l || echo 0)"
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
        # This preserves things like documentation, licenses, etc.
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
  
  # Collect overlays from all kernel packages and put them in firmware
  echo "Collecting overlays for firmware package..."
  mkdir -p "$FIRMWARE_DIR/boot/firmware/overlays"
  for pkg_dir in ${EXTRACT_DIR}/linux-image-*; do
    if [ -d "$pkg_dir" ]; then
      for kernel_dir in "$pkg_dir"/usr/lib/linux-image-*/overlays; do
        if [ -d "$kernel_dir" ]; then
          echo "  Adding overlays from $(basename $(dirname "$kernel_dir"))"
          cp -r "$kernel_dir"/* "$FIRMWARE_DIR/boot/firmware/overlays/" 2>/dev/null || true
        fi
      done
    fi
  done
  
  # Also check if there's a /boot/firmware directory already and merge it
  if [ -d "$FIRMWARE_DIR/boot/firmware" ]; then
    echo "Firmware will be installed to /boot/firmware"
    if [ -d "$FIRMWARE_DIR/boot/firmware/overlays" ]; then
      overlay_count=$(find "$FIRMWARE_DIR/boot/firmware/overlays" -name "*.dtbo" 2>/dev/null | wc -l)
      echo "  Overlay files included: $overlay_count"
    fi
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