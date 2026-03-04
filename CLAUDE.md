# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RasPINE is a hybrid operating system that combines the Raspberry Pi OS kernel/firmware with Alpine Linux userland. The build system fetches Raspberry Pi OS kernel `.deb` packages, repackages them as Alpine `.apk` packages, and creates a bootable SD card image.

- **Target**: All Raspberry Pi models (Zero/1/2/3/4/5, Compute Modules)
- **Base**: Alpine Linux v3.22 (armhf) with musl libc, OpenRC, BusyBox, Dropbear SSH
- **Kernel source**: Raspberry Pi OS (Bookworm) kernel and firmware packages
- **APK repository**: https://raspine.pistar.uk/
- **Image size**: 2GB (256MB FAT32 boot + ~1.7GB ext4 root)

## Build System

All builds run via GitHub Actions - there is no local build system. The CI pipeline runs weekly (Monday 2 AM UTC) or on manual dispatch.

### CI Pipeline (`master-build.yml`)

Orchestrates the full pipeline:
1. **check-upstream** - Compares `.last_build_info` against Raspberry Pi OS repo to detect kernel updates
2. **build-packages** - Calls `build-raspios-packages.yml` if kernel changed
3. **wait-for-repository** - Polls raspine.pistar.uk until GitHub Pages deploys new packages
4. **build-image** - Calls `build-raspine.yml` for weekly rebuild or when new packages exist
5. **create-release** - Creates GitHub Release with image artifacts (keeps last 5)
6. **update-build-info** - Commits updated `.last_build_info`

### Package Build Pipeline (`build-raspios-packages.yml`)

Builds APK packages for both `armhf` and `aarch64` using a matrix strategy. Runs inside Docker containers with QEMU emulation. Uses four scripts in sequence:

1. `scripts/raspios-fetch.sh` - Downloads `.deb` packages from `archive.raspberrypi.org/debian` (kernel images, headers, firmware). On armhf, also fetches arm64 packages for Pi 5 DTB support.
2. `scripts/raspios-extract.sh` - Extracts debs, separates kernel images/modules from DTBs/overlays. DTBs go into firmware package, kernel images go into per-variant kernel packages.
3. `scripts/raspios-apkbuild.sh` - Generates APKBUILD files with proper versioning. Checks live APKINDEX to auto-increment release numbers. Creates post-install scripts for kernel packages.
4. `scripts/raspios-build-apk.sh` - Builds APKs using `abuild` inside Docker Alpine containers. Signs packages with `keys/raspine.rsa` private key (from GitHub secrets).

### Key environment variables used across scripts
- `ARCH` - Alpine arch (`armhf` or `aarch64`)
- `VARIANTS` - Kernel variants to build (`v6 v7 v8` for armhf, `v8` for aarch64)
- `ALPINE_VERSION` - Target Alpine version (e.g., `3.22`)
- `RASPIOS_DIST` - Debian distribution codename (`bookworm`)
- `KERNEL_VERSION` - Detected kernel version from upstream

### Image Build (`build-raspine.yml`)

Runs on `ubuntu-24.04` with QEMU ARM emulation. Creates a 2GB raw image with two partitions, installs Alpine rootfs via chroot, then installs RasPINE APK packages from the live repository.

## Repository Structure

- `scripts/` - Build pipeline scripts (fetch, extract, generate APKBUILD, build APK)
- `packages/raspios-firmware/` - Template APKBUILD, `config.txt`, `cmdline.txt`, `VERSION` for firmware package
- `keys/raspine.rsa.pub` - Public key for APK package signing (private key in GitHub secrets)
- `.github/workflows/` - Three workflow files forming the CI pipeline
- `index.html` - Static landing page served via GitHub Pages at raspine.pistar.uk
- `.last_build_info` - Tracks last kernel version, build dates (auto-committed by CI)
- `CNAME` - GitHub Pages custom domain config

## Important Conventions

- Kernel variants: `v6` (Pi 1/Zero), `v7` (Pi 2), `v7l` (Pi 3 32-bit), `v8` (Pi 3/4/5 64-bit)
- DTBs and overlays are always in the firmware package, never in kernel packages
- Package versioning uses the kernel numeric version (e.g., `6.12.34`) as the APK version
- The `+rpt` suffix from Raspberry Pi kernel versions is stripped for Alpine compatibility
- Boot partition mounts at `/boot/firmware` with symlinks from `/boot/config.txt` and `/boot/cmdline.txt`
- APK repository is hosted on GitHub Pages (gh-pages branch) at raspine.pistar.uk

## Git Commit Guidelines

- Never add Claude/AI attribution to commits
- `.last_build_info` is auto-committed by CI with `[skip ci]` - do not manually edit
