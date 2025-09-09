# RasPINE - Raspberry Pi + Alpine Linux Hybrid

[![Build RasPINE Image](https://github.com/MW0MWZ/RasPINE/actions/workflows/build-raspine.yml/badge.svg)](https://github.com/MW0MWZ/RasPINE/actions/workflows/build-raspine.yml)
[![Latest Release](https://img.shields.io/github/v/release/MW0MWZ/RasPINE)](https://github.com/MW0MWZ/RasPINE/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/MW0MWZ/RasPINE/total)](https://github.com/MW0MWZ/RasPINE/releases)

RasPINE is a hybrid operating system image that combines:
- **Kernel, firmware, and modules** from Raspberry Pi OS (for maximum hardware compatibility)
- **Userland** from Alpine Linux armv6/armhf (for minimal footprint and musl libc)

## 🚀 Quick Download

**Latest Release:** [Download from raspine.pistar.uk](https://raspine.pistar.uk)

Alternative downloads:
- [GitHub Releases](https://github.com/MW0MWZ/RasPINE/releases/latest)
- [Direct Download (Latest)](https://raspine.pistar.uk/downloads/RasPINE-latest.img.xz)

## Features

- ✅ Compatible with all Raspberry Pi models (Pi 1, Zero, 2, 3, 4, 400, Zero 2 W)
- ✅ Minimal ~2GB SD card image
- ✅ Alpine Linux 3.22 userland (armv6/armhf)
- ✅ Latest Raspberry Pi OS kernel and firmware
- ✅ Automatic DHCP on ethernet
- ✅ SSH enabled by default (Dropbear)
- ✅ WiFi support included (wpa_supplicant)
- ✅ tmpfs for /var/log to reduce SD card wear
- ✅ glibc compatibility layer for kernel modules
- ✅ Monthly automated builds

## Quick Start

### Download

Download the latest release from [raspine.pistar.uk](https://raspine.pistar.uk) or [GitHub Releases](https://github.com/MW0MWZ/RasPINE/releases).

### Installation

1. Extract the image:
   ```bash
   xz -d RasPINE-YYYY-MM-DD.img.xz
   ```

2. Write to SD card (replace `/dev/sdX` with your SD card device):
   ```bash
   sudo dd if=RasPINE-YYYY-MM-DD.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```

3. Insert the SD card into your Raspberry Pi and boot

### First Login

- **Username:** `root`
- **Password:** `raspberry`
- **SSH:** Enabled on port 22

⚠️ **Security Note:** Change the root password immediately after first login!

```bash
passwd
```

## Network Configuration

### Ethernet
DHCP is enabled by default on `eth0`. No configuration needed.

### WiFi
Edit `/etc/wpa_supplicant/wpa_supplicant.conf`:

```bash
network={
    ssid="YourNetworkSSID"
    psk="YourNetworkPassword"
}
```

Then enable the wireless interface:
```bash
ifup wlan0
```

## System Management

### Package Management
Use Alpine's `apk` package manager:

```bash
# Update package index
apk update

# Install a package
apk add nano

# Search for packages
apk search nginx
```

### Services
Managed via OpenRC:

```bash
# List services
rc-status

# Start/stop/restart services
rc-service dropbear start
rc-service networking restart

# Enable/disable services at boot
rc-update add dropbear default
rc-update del dropbear default
```

## Building from Source

### Prerequisites
- GitHub account with Actions enabled
- Ubuntu 24.04 environment (or GitHub Actions)

### Build Process

1. Fork this repository
2. Enable GitHub Actions in your fork
3. Trigger a build:
   - Push to main branch, or
   - Manually trigger via Actions tab
   - Automatic monthly builds (1st of each month)

The build process takes approximately 15-20 minutes and produces:
- Compressed image (.img.xz)
- SHA256 checksum
- Build information file

## Technical Details

### Partition Layout
- **Partition 1:** 256MB FAT32 - `/boot/firmware`
- **Partition 2:** ~1.7GB ext4 - `/` (root)

### What's Included from Raspberry Pi OS
- All kernel images (kernel.img, kernel7.img, kernel7l.img, kernel8.img)
- Device tree blobs and overlays
- Kernel modules (`/lib/modules/*`)
- Firmware blobs (`/lib/firmware/*`)
- Boot configuration files
- Pi-specific udev rules

### What's from Alpine Linux
- Complete userland (musl libc based)
- OpenRC init system
- BusyBox utilities
- Alpine package manager (apk)
- Dropbear SSH server
- Network management tools

## Troubleshooting

### No Network Connection
- Check cable connection for ethernet
- Verify WiFi credentials in `/etc/wpa_supplicant/wpa_supplicant.conf`
- Check network status: `ip addr show`

### SSH Connection Refused
- Ensure dropbear is running: `rc-status`
- Start if needed: `rc-service dropbear start`

### Module Loading Errors
Some kernel modules compiled against glibc may fail. The `libc6-compat` package provides basic compatibility, but some proprietary modules may not work.

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Open a Pull Request

## License

This project combines components from:
- Raspberry Pi OS (Debian-based) - [License](https://www.raspberrypi.org/documentation/linux/kernel/license.md)
- Alpine Linux - [License](https://www.alpinelinux.org/about/)

## Acknowledgments

- Raspberry Pi Foundation for kernel and firmware
- Alpine Linux team for the minimal userland
- Community contributors

## Support

For issues and questions:
- Open an [Issue](https://github.com/MW0MWZ/RasPINE/issues)
- Check existing issues first
- Provide detailed information about your Pi model and the problem

---

**Note:** This is an experimental hybrid system. While it should work on all Pi models, some features requiring specific userland support may not function as expected.