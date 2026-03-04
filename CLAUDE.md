# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RasPINE is a hybrid operating system that combines the Raspberry Pi OS kernel/firmware with Alpine Linux userland. The build system fetches Raspberry Pi OS kernel `.deb` packages, repackages them as Alpine `.apk` packages, and creates a bootable SD card image.

- **Target**: All Raspberry Pi models (Zero/1/2/3/4/5, Compute Modules)
- **Base**: Alpine Linux v3.22 (armhf) with musl libc, OpenRC, BusyBox, Dropbear SSH
- **Kernel source**: Raspberry Pi OS (Bookworm) kernel and firmware packages
- **APK repository**: https://raspine.pistar.uk/
- **Image size**: 2GB (256MB FAT32 boot + ~1.7GB ext4 root)
- **Default credentials**: user `raspine`, password `raspberry`

## Build System

All builds run via GitHub Actions — there is no local build system or Makefile. The CI pipeline runs weekly (Monday 2 AM UTC) or on manual dispatch.

### Manual Dispatch Inputs

`master-build.yml` accepts: `force_package_update`, `skip_packages`, `build_image`. Concurrency group `master-pipeline` queues (does not cancel) concurrent runs.

### CI Pipeline (`master-build.yml`)

Orchestrates the full pipeline:
1. **check-upstream** — Compares `.last_build_info` against Raspberry Pi OS repo to detect kernel updates
2. **build-packages** — Calls `build-raspios-packages.yml` if kernel changed
3. **wait-for-repository** — Polls raspine.pistar.uk APKINDEX until new packages appear on GitHub Pages
4. **build-image** — Calls `build-raspine.yml` for weekly rebuild or when new packages exist
5. **create-release** — Creates dated GitHub Release (`vYYYY-MM-DD`) with image artifacts (keeps last 5)
6. **update-build-info** — Auto-commits updated `.last_build_info` with `[skip ci]`

### Package Build Pipeline (`build-raspios-packages.yml`)

Builds APK packages using a matrix: `arch` (armhf, aarch64) × `alpine_version` (3.22, 3.21). Runs inside Docker Alpine containers with QEMU emulation. Four scripts in sequence:

1. `scripts/raspios-fetch.sh` — Downloads `.deb` packages from `archive.raspberrypi.org/debian` (kernel images, headers, firmware). On armhf, also fetches arm64 packages for Pi 5 DTB support.
2. `scripts/raspios-extract.sh` — Extracts debs, separates kernel images/modules from DTBs/overlays. **DTBs always go into firmware package, never kernel packages.**
3. `scripts/raspios-apkbuild.sh` — Generates APKBUILD files with proper versioning. Checks live APKINDEX to auto-increment `-rN` release numbers. Creates post-install scripts that run `mkinitfs` and copy kernel images to `/boot/firmware/`.
4. `scripts/raspios-build-apk.sh` — Builds and signs APKs using `abuild` inside Docker. Signs with `raspine.rsa` private key from GitHub secrets.

After all matrix jobs, the **deploy** job:
- Merges packages to the `gh-pages` branch
- Copies aarch64 v8 packages into armhf directory (so 32-bit systems can install Pi 5 kernel)
- Regenerates signed `APKINDEX.tar.gz` and `packages.json`
- Force-pushes to `gh-pages` and optionally purges Cloudflare cache

### Source Package Pipeline (`check-source-updates.yml` + `build-source-packages.yml`)

Independent from the master pipeline. Builds packages from upstream source code (e.g., WiringPi GPIO library). `check-source-updates.yml` runs weekly (Monday 4 AM UTC, after master pipeline), compares `_gitcommit` in each APKBUILD against upstream HEAD via GitHub API, and triggers `build-source-packages.yml` only when a new upstream commit is detected.

- ARM-only matrix (armhf, aarch64) — no x86_64
- Clones upstream repo, uses commit date as `pkgver` (YYYY.MM.DD format)
- Checks existing packages across all arches/versions to determine `pkgrel`
- Builds in Docker Alpine containers with QEMU, signs with `raspine.rsa` key
- Deploy job merges into existing gh-pages content and regenerates APKINDEX for all packages
- APKBUILDs live in `packages/<name>/APKBUILD` with `giturl=` pointing to upstream and `_gitcommit=` tracking the last-built commit hash

### Image Build (`build-raspine.yml`)

Runs on `ubuntu-24.04` with QEMU ARM emulation. Creates a 2GB raw image, installs Alpine minirootfs via chroot, then installs RasPINE APK packages from the live repository. Configures OpenRC services, networking (dhcpcd), Dropbear SSH (key-only by default), WiFi modules, tmpfs mounts for `/var/log` and `/tmp`, and the `raspine-config` first-boot processor. Compresses with `xz -9`.

### Key Environment Variables

- `ARCH` — Alpine arch (`armhf` or `aarch64`)
- `VARIANTS` — Kernel variants to build (`v6 v7 v8` for armhf, `v8` for aarch64)
- `ALPINE_VERSION` — Target Alpine version (e.g., `3.22`)
- `RASPIOS_DIST` — Debian distribution codename (`bookworm`)
- `KERNEL_VERSION` — Detected kernel version from upstream

### Secrets

`APK_PRIVATE_KEY`, `GITHUB_TOKEN`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_API_TOKEN`

## Repository Structure

- `scripts/` — Build pipeline scripts (fetch, extract, generate APKBUILD, build APK)
- `packages/raspios-firmware/` — Template APKBUILD, `config.txt`, `cmdline.txt`, `VERSION` for firmware package
- `packages/wiringpi/` — WiringPi GPIO library APKBUILD (built from upstream source)
- `keys/raspine.rsa.pub` — Public key for APK package signing (private key in GitHub secrets)
- `.github/workflows/` — Five workflow files (master pipeline, kernel packages, source package check, source package build, image build)
- `index.html` — Static landing page served via GitHub Pages at raspine.pistar.uk
- `.last_build_info` — Tracks last kernel version, build dates (auto-committed by CI)

## Important Conventions

- Kernel variants: `v6` (Pi 1/Zero), `v7` (Pi 2/3 32-bit), `v8` (Pi 3/4/5 64-bit)
- DTBs and overlays are always in the firmware package, never in kernel packages
- Package versioning uses the kernel numeric version (e.g., `6.12.34`) as the APK version
- The `+rpt` suffix from Raspberry Pi kernel versions is stripped for Alpine compatibility
- Boot partition mounts at `/boot/firmware` with symlinks from `/boot/config.txt` and `/boot/cmdline.txt`
- APK repository is hosted on GitHub Pages (gh-pages branch) at raspine.pistar.uk
- APKBUILD files use `options="!check !strip !tracedeps !fhs"` to accommodate non-standard layouts
- No test infrastructure exists; verification is operational (signature checks, APKINDEX polling, boot file existence)

## Git Commit Guidelines

- Never add Claude/AI attribution to commits
- `.last_build_info` is auto-committed by CI with `[skip ci]` — do not manually edit
