# 🏔️ RasPINE - Raspberry Pi + Alpine Linux Hybrid

[![Build Status](https://github.com/MW0MWZ/RasPINE/actions/workflows/master-build.yml/badge.svg)](https://github.com/MW0MWZ/RasPINE/actions/workflows/master-build.yml)
[![Latest Release](https://img.shields.io/github/v/release/MW0MWZ/RasPINE)](https://github.com/MW0MWZ/RasPINE/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/MW0MWZ/RasPINE/total)](https://github.com/MW0MWZ/RasPINE/releases)
[![Alpine Version](https://img.shields.io/badge/Alpine-v3.22-0D597F)](https://alpinelinux.org)
[![Kernel](https://img.shields.io/badge/dynamic/json?url=https://raspine.pistar.uk/packages.json&query=$.kernel_version&label=Kernel&color=c51a4a)](https://www.raspberrypi.org)

> **The best of both worlds:** Raspberry Pi OS kernel and firmware for perfect hardware compatibility, combined with Alpine Linux userland for minimal footprint and efficiency.

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🔧 **Maximum Compatibility** | Uses official Raspberry Pi OS kernel and firmware for perfect hardware support |
| 🪶 **Minimal Footprint** | Alpine Linux userland with musl libc - fits on a 2GB SD card |
| 🔒 **Secure by Default** | SSH enabled with Dropbear, minimal attack surface |
| 📦 **Modern Package Management** | Alpine's apk package manager with vast repository access |
| 🌐 **Network Ready** | DHCP on ethernet, WiFi support with wpa_supplicant |
| 💾 **SD Card Friendly** | /var/log on tmpfs to reduce wear on your SD card |
| 🔄 **Weekly Updates** | Automated builds with latest Raspberry Pi OS kernels |

## 🚀 Quick Start

### 1️⃣ Download the Latest Image

<div align="center">

**[📥 Download Latest Release](https://github.com/MW0MWZ/RasPINE/releases/latest)**

Alternative downloads:
[All Releases](https://github.com/MW0MWZ/RasPINE/releases) | 
[Direct Download](https://github.com/MW0MWZ/RasPINE/releases/latest/download/RasPINE-latest.img.xz) | 
[SHA256 Checksum](https://raspine.pistar.uk/downloads/RasPINE-latest.img.xz.sha256)

</div>

### 2️⃣ Write to SD Card

```bash
# Extract the image
xz -d RasPINE-YYYY-MM-DD.img.xz

# Write to SD card (replace /dev/sdX with your SD card device)
sudo dd if=RasPINE-YYYY-MM-DD.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### 3️⃣ First Boot

Insert the SD card and power on your Raspberry Pi. Connect via SSH or console:

- **Username:** `raspine`
- **Password:** `raspberry`

> ⚠️ **Security Note:** Change the password immediately after first login using `passwd`

## 🥧 Compatibility

RasPINE works with **ALL** Raspberry Pi models:

| Series | Models |
|--------|--------|
| **Classic** | Pi 1 Model A/B/B+ |
| **Zero** | Pi Zero, Zero W, Zero 2 W |
| **Standard** | Pi 2B, 3A+/B/B+, 4B, 5 |
| **Compute** | CM1, CM3, CM3+, CM4, CM4S |
| **Special** | Pi 400, Pi 500 |

## 📡 Network Configuration

### Ethernet
DHCP is enabled by default on `eth0`. No configuration needed.

### WiFi Setup
Edit `/etc/wpa_supplicant/wpa_supplicant.conf`:

```bash
network={
    ssid="YourNetworkSSID"
    psk="YourNetworkPassword"
}
```

Then enable the wireless interface:
```bash
sudo ifup wlan0
```

## 📦 Package Management

RasPINE uses Alpine's `apk` package manager:

```bash
# Update package index
apk update

# Install packages
apk add nano htop git

# Search for packages
apk search nginx

# Remove packages
apk del package-name
```

### Custom APK Repository

RasPINE includes the custom RasPINE repository with Raspberry Pi OS kernels and firmware:

```bash
# Already configured in the image
https://raspine.pistar.uk/v3.22/community
```

## 🛠️ System Management

### Service Management (OpenRC)

```bash
# List all services
rc-status

# Start/stop/restart services
rc-service dropbear start
rc-service networking restart

# Enable/disable at boot
rc-update add dropbear default
rc-update del dropbear default
```

### System Information

```bash
# Check Alpine version
cat /etc/alpine-release

# Check kernel version
uname -r

# Check disk usage
df -h

# Check memory usage
free -h
```

## 🏗️ Technical Architecture

### Partition Layout

| Partition | Size | Format | Mount Point | Purpose |
|-----------|------|--------|-------------|---------|
| 1 | 256MB | FAT32 | `/boot/firmware` | Boot files, kernel, firmware |
| 2 | ~1.7GB | ext4 | `/` | Root filesystem |

### What Comes From Where?

#### From Raspberry Pi OS:
- All kernel images (kernel*.img)
- Device tree blobs and overlays
- Kernel modules (`/lib/modules/*`)
- Firmware blobs (`/lib/firmware/*`)
- Boot configuration files
- Hardware-specific udev rules

#### From Alpine Linux:
- Complete userland (musl libc)
- OpenRC init system
- BusyBox utilities
- APK package manager
- Dropbear SSH server
- Network management tools

## 🐛 Troubleshooting

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| **No network** | Check cable/WiFi config, verify with `ip addr show` |
| **SSH refused** | Ensure dropbear is running: `rc-status` |
| **Module errors** | Some glibc modules may fail; `libc6-compat` provides basic compatibility |
| **Boot issues** | Check `/boot/firmware/config.txt` and `cmdline.txt` |
| **Package not found** | Run `apk update` first |

### Getting Help

Check the [Issues](https://github.com/MW0MWZ/RasPINE/issues) page or create a new issue if you encounter problems.

## 🤝 Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development

```bash
# Clone the repository
git clone https://github.com/MW0MWZ/RasPINE.git
cd RasPINE

# Make your changes
# Test locally if possible
# Submit a pull request
```

## 📄 License

This project combines components from:
- **Raspberry Pi OS** - [Raspberry Pi OS License](https://www.raspberrypi.org/documentation/linux/kernel/license.md)
- **Alpine Linux** - [Alpine License](https://www.alpinelinux.org/about/)

## 🙏 Acknowledgments

- [Raspberry Pi Foundation](https://www.raspberrypi.org) for kernel and firmware
- [Alpine Linux Team](https://alpinelinux.org) for the minimal userland
- [Pi-Star Team](https://www.pistar.uk) for inspiration and collaboration
- The Amateur Radio community for continuous support

## 📊 Project Stats

![GitHub Stars](https://img.shields.io/github/stars/MW0MWZ/RasPINE?style=social)
![GitHub Forks](https://img.shields.io/github/forks/MW0MWZ/RasPINE?style=social)
![GitHub Watchers](https://img.shields.io/github/watchers/MW0MWZ/RasPINE?style=social)

---

<div align="center">

**Built with ❤️ for the Raspberry Pi and Amateur Radio communities**

*Maintained by Andy Taylor (MW0MWZ)*

[Website](https://raspine.pistar.uk) | [Downloads](https://github.com/MW0MWZ/RasPINE/releases)

</div>