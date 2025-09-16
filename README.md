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
| ⚙️ **Zero-Touch Configuration** | Configure WiFi, SSH, and system settings before first boot |
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

### 3️⃣ (Optional) Configure Before First Boot

RasPINE supports zero-touch configuration! Mount the boot partition after writing the image and create a configuration file:

```bash
# Mount the boot partition (adjust device as needed)
mkdir -p /mnt/boot
mount /dev/sdX1 /mnt/boot

# Copy and edit the configuration template
cp /mnt/boot/raspine-config.txt.sample /mnt/boot/raspine-config.txt
nano /mnt/boot/raspine-config.txt

# Unmount when done
umount /mnt/boot
```

See the [Boot Configuration](#-boot-configuration) section for details on available options.

### 4️⃣ First Boot

Insert the SD card and power on your Raspberry Pi. Connect via SSH or console:

- **Username:** `raspine`
- **Password:** `raspberry` (or your configured password)

> ⚠️ **Security Note:** Change the password immediately after first login using `passwd`

## ⚙️ Boot Configuration

RasPINE includes a powerful boot configuration system that allows you to set up your system before the first boot. This is perfect for headless deployments or when you need to configure multiple devices.

### How It Works

1. On the boot partition, you'll find `raspine-config.txt.sample`
2. Copy this to `raspine-config.txt` and edit with your settings
3. On first boot, RasPINE processes this file and applies your configuration
4. **The config file is automatically deleted after processing for security**

### Configuration Options

#### WiFi Networks

Configure multiple WiFi networks with priority ordering:

```ini
# Primary network (highest priority if not numbered)
wifi_ssid=HomeNetwork
wifi_password=HomePassword

# Additional networks with priority (higher numbers = higher priority)
wifi_ssid_2=WorkNetwork
wifi_password_2=WorkPassword

wifi_ssid_3=MobileHotspot
wifi_password_3=HotspotPassword

# WiFi country code (affects available channels)
wifi_country=GB

# Allow connection to open networks
enable_open_networks=false
```

#### User Security

```ini
# Set password for raspine user
user_password=MySecurePassword

# Enable SSH password authentication (default is key-only)
enable_ssh_password=true

# Add SSH public key for secure access
ssh_key=ssh-rsa AAAAB3NzaC1yc2EAAAA... user@example.com
```

#### System Settings

```ini
# Set hostname
hostname=my-raspine

# Set timezone
timezone=Europe/London

# Set locale
locale=en_GB.UTF-8
```

### Complete Example

```ini
# RasPINE Boot Configuration
# WARNING: This file will be DELETED after processing for security!

# === WIFI CONFIGURATION ===
wifi_ssid=MyHomeNetwork
wifi_password=MyHomePassword

wifi_ssid_2=WorkNetwork
wifi_password_2=WorkPassword

wifi_country=GB
enable_open_networks=false

# === USER SECURITY ===
user_password=MySecurePassword123!
enable_ssh_password=false
ssh_key=ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDEx... user@example.com

# === SYSTEM CONFIGURATION ===
hostname=raspine-zero
timezone=Europe/London
locale=en_GB.UTF-8
```

### Security Notes

- The configuration file is **automatically deleted** after processing to protect your passwords
- WiFi passwords and user passwords are never stored in plain text after configuration
- SSH key-only authentication is recommended for production use
- Always keep a backup of your configuration in a secure location

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

#### Method 1: Boot Configuration (Recommended)
Use the boot configuration system described above to set up WiFi before first boot.

#### Method 2: Manual Configuration
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
| 1 | 256MB | FAT32 | `/boot/firmware` | Boot files, kernel, firmware, config |
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

#### RasPINE Specific:
- Boot configuration processor (`raspine-config`)
- Hybrid integration scripts
- Custom APK repository configuration

## 🐛 Troubleshooting

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| **No network** | Check cable/WiFi config, verify with `ip addr show` |
| **WiFi not connecting** | Check country code, verify password, check `wpa_supplicant` logs |
| **SSH refused** | Ensure dropbear is running: `rc-status` |
| **Config not applied** | Config file must be named exactly `raspine-config.txt` |
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