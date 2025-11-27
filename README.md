# Looking Glass VFIO Setup

Production-ready Looking Glass setup for GPU passthrough from Ubuntu/Fedora host to Windows 11 guest using QEMU/KVM/libvirt.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Manual Installation](#manual-installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)
- [References](#references)

## Overview

This repository provides a complete, modular solution for setting up a Windows 11 VM with GPU passthrough and Looking Glass for near-native gaming performance. The setup includes:

- **Automated deployment** via Ansible playbooks
- **Modular shell libraries** for easy customization
- **Libvirt hooks** for automatic host preparation
- **Looking Glass integration** for low-latency display
- **Best practices** from the VFIO community

### System Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Linux Host (Ubuntu/Fedora)                              │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Looking Glass Client                               │ │
│  │ (Display output from VM)                           │ │
│  └─────────────────┬──────────────────────────────────┘ │
│                    │ Shared Memory                      │
│  ┌─────────────────┴──────────────────────────────────┐ │
│  │ Windows 11 VM (QEMU/KVM)                           │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │ Looking Glass Host (ivshmem)                 │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │ Passed-through GPU (NVIDIA/AMD)              │  │ │
│  │  │ - Direct hardware access                     │  │ │
│  │  │ - Native driver support                      │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Features

### Core Features

- ✅ **GPU Passthrough** - Direct GPU access for native performance
- ✅ **Looking Glass** - Low-latency display streaming (< 1ms overhead)
- ✅ **Windows 11 Support** - TPM 2.0 emulation and Secure Boot
- ✅ **CPU Pinning** - Optimized CPU core allocation
- ✅ **Hugepages** - Reduced memory latency
- ✅ **SPICE Integration** - Audio, USB, and clipboard sharing
- ✅ **Evdev Input** - Direct keyboard/mouse passthrough
- ✅ **Dual Network Interfaces** - Virtual NAT + direct physical NIC access (macvtap)

### Automation Features

- ✅ **Ansible Deployment** - One-command setup with modular task organization
- ✅ **Libvirt Hooks** - Automatic display manager management
- ✅ **Modular Scripts** - Reusable library functions
- ✅ **Configuration Templates** - Easy customization
- ✅ **Auto Hardware Detection** - GPU, CPU, SMBIOS auto-discovery
- ✅ **Auto Network Configuration** - Automatic physical NIC detection for macvtap

### Supported Configurations

- **Host OS**: Ubuntu 22.04+, Fedora 38+, Arch Linux
- **Guest OS**: Windows 11, Windows 10
- **GPUs**: NVIDIA, AMD (single or multi-GPU)
- **CPUs**: AMD Ryzen, Intel Core (IOMMU required)

## Prerequisites

### Hardware Requirements

1. **CPU**: Must support virtualization and IOMMU
   - Intel: VT-x and VT-d
   - AMD: AMD-V and AMD-Vi

2. **GPU**: Dedicated GPU for passthrough
   - NVIDIA GTX/RTX series
   - AMD Radeon RX series
   - Second GPU or integrated graphics for host (recommended)

3. **Memory**: Minimum 16GB RAM (32GB+ recommended)

4. **Storage**: NVMe SSD recommended for VM disk

### Software Requirements

- QEMU/KVM
- libvirt
- OVMF (UEFI firmware)
- Ansible (for automated setup)

### BIOS/UEFI Settings

Enable the following in your BIOS:

- ✅ Intel VT-x / AMD-V (Virtualization)
- ✅ Intel VT-d / AMD-Vi (IOMMU)
- ✅ UEFI Boot Mode
- ✅ Disable Secure Boot (temporarily, for setup)

## Quick Start

### ⚡ Fully Automated Setup (Recommended)

**Single command - complete installation:**

```bash
# Clone the repository
git clone https://github.com/yourusername/ansible_lookingglass.git
cd ansible_lookingglass

# Run automated setup
./setup.sh
```

**Note:** The script will prompt for sudo password only when needed (package installation, system configuration). By default, it stores VM files in `$HOME/libvirt/images` to avoid unnecessary privilege escalation.

**What it does (8 automated phases):**

| Phase | Tasks | Duration |
|-------|-------|----------|
| **0. User Preferences** | Ask storage location, configure paths | ~5 sec |
| **1. Prerequisites** | Install qemu-kvm, libvirt, virt-manager, verify IOMMU | ~2 min |
| **2. Hardware Detection** | Auto-detect GPU, CPU, SMBIOS (BIOS/motherboard info) | ~5 sec |
| **3. Download ISOs** | Download VirtIO drivers, prompt for Windows 11 ISO | ~1 min |
| **4. Host Configuration** | Configure hugepages, system tuning | ~10 sec |
| **5. VFIO Setup** | Install hooks, libraries for GPU switching | ~15 sec |
| **6. VM Creation** | Generate XML with full VM evasion, define in libvirt | ~20 sec |
| **7. Launch** | Start VM, open virt-manager | ~5 sec |

**Total time: ~5 minutes** (excluding Windows installation)

The script is **fully idempotent** (safe to run multiple times) and uses Ansible for reliability.

### 🎛️ Customization Options

```bash
# Custom VM name and specs
VM_NAME=gaming VM_MEMORY_GB=32 VM_VCPUS=16 ./setup.sh

# Custom storage location (defaults to user home directory)
VM_STORAGE_DIR=$HOME/libvirt/images ./setup.sh

# Use system directory (requires sudo for file operations)
VM_STORAGE_DIR=/var/lib/libvirt/images ./setup.sh

# Automatically replace existing VM without prompting
AUTO_REPLACE_VM=true ./setup.sh

# Skip auto-start (create VM without starting)
AUTO_START_VM=false ./setup.sh

# Skip Windows ISO check
SKIP_ISO_DOWNLOAD=true WINDOWS_ISO=/path/to/win11.iso ./setup.sh
```

**Environment Variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_NAME` | `win11` | Name of the VM to create |
| `VM_MEMORY_GB` | `16` | RAM allocation in GB |
| `VM_VCPUS` | `12` | Number of CPU cores |
| `VM_STORAGE_DIR` | Interactive prompt | Storage directory for ISOs and disk images |
| `AUTO_REPLACE_VM` | `false` | Replace existing VM without prompting |
| `AUTO_START_VM` | `true` | Start VM after creation |
| `SKIP_ISO_DOWNLOAD` | `false` | Skip Windows ISO download check |
| `WINDOWS_ISO` | Auto-detected | Path to Windows 11 ISO file |
| `PHYSICAL_NIC` | Auto-detected | Physical network interface for macvtap (e.g., `enp7s0`) |

---

### 🔧 Manual Setup (Advanced)

<details>
<summary>Click to expand manual installation steps</summary>

### 1. Enable IOMMU

Add kernel parameters to enable IOMMU:

**For Intel:**
```bash
# Edit /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

**For AMD:**
```bash
# Edit /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
```

Update GRUB and reboot:
```bash
sudo update-grub  # Ubuntu/Debian
sudo grub2-mkconfig -o /boot/grub2/grub.cfg  # Fedora
sudo reboot
```

### 2. Verify IOMMU Groups

```bash
bash find_iommu.sh
```

Find your GPU's PCI address:
```bash
lspci -nn | grep -i vga
```

### 3. Configure Ansible Inventory

```bash
cd ansible
cp inventory.yml inventory.local.yml
vim inventory.local.yml
```

Edit the following variables:
```yaml
vm_name: win11
vm_memory_gb: 16
vm_vcpus: 12
gpu_pci_video: "0000:06:00.0"  # Your GPU address
gpu_pci_audio: "0000:06:00.1"  # Your GPU audio
bridge_interface: enp6s0        # Your network interface
```

### 4. Run Ansible Playbook

```bash
cd ansible
ansible-playbook -i inventory.local.yml playbook.yml --ask-become-pass
```

### 5. Create Windows 11 VM Disk

```bash
sudo qemu-img create -f qcow2 /var/lib/libvirt/images/win11.qcow2 120G
```

### 6. Define and Start VM

```bash
sudo virsh define /usr/local/share/vfio-setup/win11.xml
sudo virsh start win11
```

</details>

### 7. Install and Configure Windows 11

Install Windows 11 in the VM using the passed-through GPU:

1. **Initial Setup**: Use virt-manager or SPICE to see the VM during Windows installation
   ```bash
   virt-manager
   # Or connect via SPICE
   remote-viewer spice://localhost:5900
   ```

2. **Install Windows 11** as normal

3. **Install VirtIO drivers** for network/storage if using virtio devices
   - Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/

4. **Install GPU drivers** (NVIDIA/AMD) inside Windows

### 8. Install Looking Glass

**IMPORTANT**: Looking Glass runs **backwards** from what you might expect:
- **Windows (Guest)** = Runs Looking Glass **HOST** application (captures and shares display)
- **Linux (Host)** = Runs Looking Glass **CLIENT** (views the shared display)

#### On Windows 11 (Guest VM):

1. **Download Looking Glass Host**
   - Visit: https://looking-glass.io/downloads
   - Download latest stable release (e.g., `looking-glass-host-setup-B6.exe`)

2. **Install IVSHMEM Driver**
   ```
   a. Download the latest IVSHMEM driver from Looking Glass downloads
   b. Extract the driver package
   c. Open Device Manager (Win+X → Device Manager)
   d. Find "PCI standard RAM Controller" under "System devices"
   e. Right-click → Update driver → Browse my computer
   f. Point to extracted IVSHMEM driver folder
   g. Install the driver
   ```

3. **Install Looking Glass Host Application**
   - Run the installer (`looking-glass-host-setup-B6.exe`)
   - Choose installation directory (default: `C:\Program Files\Looking Glass (host)`)
   - **Important**: Check "Install as Service" option
   - Complete installation

4. **Configure Looking Glass Host**

   Create config file: `C:\ProgramData\Looking Glass (host)\looking-glass-host.ini`
   ```ini
   [app]
   shmFile=looking-glass

   [capture]
   # Use DXGI for NVIDIA, or D3D12 for AMD
   captureAPI=DXGI

   # Capture settings
   throttleFPS=0

   [audio]
   enabled=true

   [spice]
   enabled=true
   ```

5. **Start Looking Glass Host Service**
   ```
   Option A: Reboot Windows (service auto-starts)

   Option B: Start manually
   - Open Services (Win+R → services.msc)
   - Find "Looking Glass (host)"
   - Right-click → Start
   ```

6. **Verify it's running**
   - Check system tray for Looking Glass icon
   - Or check Services to confirm it's running

#### On Linux (Host):

1. **Install Looking Glass Client**

   **Ubuntu/Debian:**
   ```bash
   sudo apt update
   sudo apt install looking-glass-client
   ```

   **Fedora:**
   ```bash
   sudo dnf install looking-glass-client
   ```

   **Arch:**
   ```bash
   sudo pacman -S looking-glass
   ```

   **Build from source** (latest features):
   ```bash
   # Install dependencies
   sudo apt install binutils-dev cmake fonts-dejavu-core \
     libfontconfig-dev gcc g++ pkg-config libegl-dev libgl-dev \
     libgles-dev libspice-protocol-dev nettle-dev libx11-dev \
     libxcursor-dev libxi-dev libxinerama-dev libxpresent-dev \
     libxss-dev libxkbcommon-dev libwayland-dev wayland-protocols \
     libpipewire-0.3-dev libpulse-dev libsamplerate0-dev

   # Clone and build
   git clone --recursive https://github.com/gnif/LookingGlass.git
   cd LookingGlass
   mkdir client/build
   cd client/build
   cmake ../
   make
   sudo make install
   ```

2. **Configure permissions** (for shared memory access)

   The automated setup creates a tmpfiles.d configuration for you. To install it manually:

   ```bash
   # Install tmpfiles.d config (created by setup in ~/.local/share/vfio-setup/)
   sudo cp ~/.local/share/vfio-setup/10-looking-glass.conf /etc/tmpfiles.d/

   # Create the shared memory file with correct permissions
   sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf

   # Add yourself to kvm group
   sudo usermod -a -G kvm $USER

   # Log out and back in for group to take effect
   ```

   **What this does:**
   - Sets `/dev/shm/looking-glass` permissions to 0660 (read/write for owner and group)
   - Sets ownership to `libvirt-qemu:kvm`
   - Allows users in the `kvm` group to access Looking Glass without sudo

3. **Create Looking Glass client config** (optional)

   `~/.config/looking-glass/client.ini`:
   ```ini
   [app]
   shmFile=/dev/shm/looking-glass

   [win]
   fullScreen=yes
   showFPS=yes

   [input]
   grabKeyboard=yes
   escapeKey=KEY_SCROLLLOCK

   [spice]
   enable=yes
   audio=yes
   ```

4. **Run Looking Glass Client**
   ```bash
   # Basic
   looking-glass-client

   # With options
   looking-glass-client -F  # Fullscreen
   looking-glass-client -F -p 0  # Fullscreen, no SPICE cursor
   looking-glass-client -F -K 200  # Fullscreen, 200Hz refresh
   ```

5. **Client Keyboard Shortcuts**
   - `Scroll Lock` - Capture/release mouse and keyboard
   - `Scroll Lock + Q` - Quit client
   - `Scroll Lock + F` - Toggle fullscreen
   - `Scroll Lock + V` - Toggle video synchronization
   - `Scroll Lock + I` - Show FPS and latency information
   - `Scroll Lock + R` - Rotate display
   - `Scroll Lock + T` - Toggle frame timing display

### 9. Verify Everything Works

1. **Start the VM**
   ```bash
   virsh start win11
   ```

2. **Wait for Windows to boot** (check SPICE if needed)

3. **Launch Looking Glass client**
   ```bash
   looking-glass-client -F
   ```

4. **You should see** your Windows desktop with near-native performance!

**Troubleshooting if you see a black screen:**
- Ensure Windows booted completely
- Check Looking Glass Host is running in Windows Task Manager
- Verify IVSHMEM device is working in Device Manager
- Check shared memory exists: `ls -lh /dev/shm/looking-glass`

## Manual Installation

If you prefer manual setup without Ansible:

### 1. Install Dependencies

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils \
  virt-manager ovmf dnsmasq
```

**Fedora:**
```bash
sudo dnf install @virtualization
```

### 2. Copy Files

```bash
sudo mkdir -p /usr/local/share/vfio-setup/{lib,scripts,config}
sudo cp lib/vfio-common.sh /usr/local/share/vfio-setup/lib/
sudo cp scripts/* /usr/local/share/vfio-setup/scripts/
sudo chmod +x /usr/local/share/vfio-setup/scripts/*
```

### 3. Create Configuration

```bash
sudo cp config/vfio.conf.example /usr/local/share/vfio-setup/config/vfio.conf
sudo vim /usr/local/share/vfio-setup/config/vfio.conf
```

### 4. Install Libvirt Hook

```bash
sudo mkdir -p /etc/libvirt/hooks
sudo cp hooks/qemu.new /etc/libvirt/hooks/qemu
sudo chmod +x /etc/libvirt/hooks/qemu
```

### 5. Create Libvirt No-Sleep Service

```bash
sudo tee /etc/systemd/system/libvirt-nosleep@.service > /dev/null <<'EOF'
[Unit]
Description=Preventing sleep while libvirt domain "%i" is running

[Service]
Type=simple
ExecStart=/usr/bin/systemd-inhibit --what=sleep --why="Libvirt domain %i is running" --who=%U --mode=block sleep infinity
EOF

sudo systemctl daemon-reload
```

## Configuration

### Primary Configuration File

Location: `/usr/local/share/vfio-setup/config/vfio.conf`

```bash
# VM Configuration
VM_NAME="win11"

# CPU Pinning
HOST_PINNED_CPUS="12-19"  # Cores for host when VM running
ALL_CPUS="0-19"           # All cores when VM stopped

# Memory
ENABLE_HUGEPAGES=true
HUGEPAGES_COUNT=8192      # (VM_RAM_GB * 1024) / 2

# Looking Glass
LOOKING_GLASS_SIZE=256    # 32=1080p, 64=1440p, 128=4K, 256=4K HDR

# Performance
ENABLE_PERFORMANCE_TWEAKS=true
ENABLE_CPU_GOVERNOR=false
```

### VM XML Configuration

Location: `/usr/local/share/vfio-setup/win11.xml`

Key sections to customize:

#### Memory
```xml
<memory unit='KiB'>16777216</memory>  <!-- 16GB -->
```

#### CPU Topology
```xml
<vcpu placement="static">12</vcpu>
<topology sockets='1' dies='1' cores='6' threads='2'/>
```

#### GPU Passthrough
```xml
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
  </source>
</hostdev>
```

## Usage

### Starting the VM

**Automatic (hooks enabled):**
```bash
virsh start win11
```
The hook will automatically:
- Stop display manager
- Unload GPU drivers
- Load VFIO drivers
- Allocate hugepages
- Apply performance tweaks

**Manual:**
```bash
sudo /usr/local/share/vfio-setup/scripts/vfio-start
virsh start win11
```

### Stopping the VM

**Automatic:**
```bash
virsh shutdown win11
```
The hook will automatically restore the host.

**Manual:**
```bash
virsh shutdown win11
sudo /usr/local/share/vfio-setup/scripts/vfio-stop
```

### Connecting with Looking Glass

```bash
looking-glass-client -F
```

Keyboard shortcuts:
- `Scroll Lock` - Capture/release input
- `Scroll Lock + Q` - Quit
- `Scroll Lock + F` - Toggle fullscreen
- `Scroll Lock + I` - Show FPS/latency stats

## Troubleshooting

### IOMMU Not Enabled

**Symptoms:** VM fails to start with VFIO errors

**Solution:**
```bash
# Check if IOMMU is enabled
dmesg | grep -i iommu

# If not, add kernel parameter and reboot
# Intel: intel_iommu=on
# AMD: amd_iommu=on
```

### GPU Not Isolated

**Symptoms:** "Device is in use" errors

**Solution:**
```bash
# Check what's using the GPU
lsof /dev/nvidia* /dev/dri/*

# Ensure display manager is stopped
sudo systemctl status display-manager

# Check VFIO drivers loaded
lsmod | grep vfio
```

### Display Manager Won't Stop

**Symptoms:** Black screen but DM still running

**Solution:**
```bash
# Check logs
tail -f /var/log/libvirt/vfio.log

# Manually stop
sudo systemctl stop gdm      # GNOME
sudo systemctl stop sddm     # KDE
sudo systemctl stop lightdm  # XFCE
```

### NVRAM Permission Denied Error

**Symptoms:** VM fails to start with error:
```
Could not open '/path/to/nvram/win11_VARS.fd': Permission denied
```

**Solution:**

**Quick Fix (Recommended):**
```bash
./fix_nvram.sh
# Or for a different VM name:
./fix_nvram.sh your-vm-name
```

**Manual Fix:**
```bash
# For session mode (user-level libvirt)
chmod 600 ~/.local/share/libvirt/qemu/nvram/win11_VARS.fd
chown $USER ~/.local/share/libvirt/qemu/nvram/win11_VARS.fd

# For system mode (root-level libvirt)
sudo chmod 644 /var/lib/libvirt/qemu/nvram/win11_VARS.fd
sudo chown root:root /var/lib/libvirt/qemu/nvram/win11_VARS.fd
```

**Using Ansible:**
```bash
cd ansible
VM_NAME=win11 ansible-playbook fix_nvram.yml
```

**Root Cause:**
This occurs when libvirt creates NVRAM files with incorrect permissions, especially in session mode. The automated setup now includes a fix for this issue.

### Looking Glass Black Screen

**Symptoms:** Client shows black screen

**Solution:**
1. Ensure Looking Glass host is running in Windows
2. Check shared memory: `ls -lh /dev/shm/looking-glass`
3. Verify IVSHMEM device in VM:
   ```bash
   virsh dumpxml win11 | grep -A5 shmem
   ```
4. Check Windows Device Manager for IVSHMEM device

### Looking Glass Permission Denied

**Symptoms:** `looking-glass-client` fails with "Permission denied" on `/dev/shm/looking-glass`

**Solution:**
```bash
# Install the tmpfiles.d configuration (automated setup creates this)
sudo cp ~/.local/share/vfio-setup/10-looking-glass.conf /etc/tmpfiles.d/
sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf

# Ensure you're in the kvm group
sudo usermod -a -G kvm $USER

# Restart the VM to recreate the shared memory file
virsh shutdown win11
virsh start win11

# Try Looking Glass client again
looking-glass-client
```

### Poor Performance

**Symptoms:** Low FPS, stuttering

**Solution:**
```bash
# Verify CPU pinning
virsh vcpuinfo win11

# Check hugepages allocated
cat /proc/sys/vm/nr_hugepages

# Verify MSI interrupts (better than legacy)
lspci -v | grep MSI

# Enable performance mode
sudo cpupower frequency-set -g performance
```

## Advanced Configuration

### Single GPU Passthrough

If you only have one GPU, use the hooks to unload drivers:

```bash
# The vfio-startup.sh script handles this automatically
# It will:
# 1. Stop display manager
# 2. Unload GPU drivers
# 3. Switch to VT console
# 4. Load VFIO drivers
```

### Multi-Monitor Setup

For multiple monitors in Looking Glass:

1. Configure all monitors in Windows
2. Start Looking Glass client:
   ```bash
   looking-glass-client -F -m <monitor-number>
   ```

### USB Device Passthrough

Find USB device IDs:
```bash
lsusb
```

Add to VM XML:
```xml
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <vendor id='0x1234'/>
    <product id='0x5678'/>
  </source>
</hostdev>
```

### VirtioFS File Sharing

Add shared folder to VM XML:
```xml
<filesystem type='mount' accessmode='passthrough'>
  <driver type='virtiofs' queue='1024'/>
  <source dir='/home/user/shared'/>
  <target dir='share'/>
</filesystem>
```

In Windows, install WinFsp and mount the share.

### CPU Topology Optimization

**AMD Ryzen 7950X3D (with 3D V-Cache):**
```xml
<vcpu placement='static' cpuset='0-7,16-23'>16</vcpu>
<topology sockets='1' dies='1' cores='8' threads='2'/>
```
Give VM the V-Cache CCX cores for best gaming performance.

**Intel 12700KF (P-cores + E-cores):**
```xml
<vcpu placement="static">12</vcpu>
<topology sockets='1' dies='1' cores='6' threads='2'/>
<vcpupin vcpu='0' cpuset='0'/>  <!-- P-cores only -->
```
Pin P-cores (performance) to VM, E-cores to host.

### Network Configuration

The automated setup creates **dual network interfaces** for your VM:

1. **Virtual Bridge (NAT)** - Default virtualized network
2. **Macvtap (Direct Physical)** - Direct access to your physical NIC for LAN connectivity

**Automatic Detection:**
The setup auto-detects your primary physical network interface. You can override:
```bash
PHYSICAL_NIC=enp7s0 ./setup.sh
```

**Manual Network Bridge Setup:**

If you need custom bridge configuration:

**Using NetworkManager:**
```bash
nmcli connection add type bridge ifname br0 con-name br0
nmcli connection add type bridge-slave ifname enp6s0 master br0
nmcli connection up br0
```

**Manual:**
```bash
ip link add br0 type bridge
ip link set enp6s0 master br0
ip link set br0 up
dhclient br0
```

## Project Structure

```
.
├── ansible/                          # Automated deployment (modular)
│   ├── setup_complete.yml           # Main orchestrator playbook
│   ├── fix_nvram.yml                # NVRAM permission fix
│   ├── prescan_hardware.yml         # Pre-sudo hardware scan
│   │
│   ├── tasks/                       # Modular task organization
│   │   ├── prerequisites/           # System prerequisite checks
│   │   │   ├── main.yml            # Orchestrator
│   │   │   ├── packages.yml        # QEMU/libvirt package verification
│   │   │   ├── iommu.yml           # IOMMU group detection
│   │   │   ├── services.yml        # libvirtd service check
│   │   │   └── user_groups.yml     # Group membership verification
│   │   │
│   │   ├── detect_hardware/         # Hardware auto-detection
│   │   │   ├── main.yml            # Orchestrator + saves results
│   │   │   ├── gpu.yml             # GPU PCI address detection
│   │   │   ├── firmware.yml        # OVMF firmware path detection
│   │   │   ├── cpu.yml             # CPU vendor/core count
│   │   │   └── smbios.yml          # BIOS/System/Baseboard info
│   │   │
│   │   ├── create_vm/               # VM creation and configuration
│   │   │   ├── main.yml            # Orchestrator
│   │   │   ├── network.yml         # MAC generation, macvtap setup
│   │   │   ├── storage.yml         # Disk image creation
│   │   │   └── definition.yml      # XML generation, VM definition
│   │   │
│   │   ├── user_preferences.yml    # Storage location selection
│   │   ├── download_isos.yml       # VirtIO drivers, Windows ISO
│   │   ├── configure_host.yml      # Hugepages recommendations
│   │   ├── install_vfio.yml        # VFIO hooks/scripts installation
│   │   ├── start_vm.yml            # VM startup and virt-manager
│   │   └── show_instructions.yml   # Post-setup instructions
│   │
│   └── templates/                   # Jinja2 templates
│       ├── vm-config.xml.j2        # VM XML with anti-detection
│       ├── qemu.hook.j2            # Libvirt hook template
│       ├── vfio-start.j2           # GPU switching script
│       ├── vfio-stop.j2            # GPU restore script
│       └── vfio-common.sh.j2       # Shared library functions
│
├── lib/                             # Shared libraries
│   └── vfio-common.sh              # Common shell functions
│
├── scripts/                         # Helper scripts
│   ├── vfio-start                  # GPU switching (start VM)
│   └── vfio-stop                   # GPU restore (stop VM)
│
├── archive/                         # Deprecated/obsolete files
│   ├── ansible/                    # Old monolithic task files
│   └── *.sh                        # Legacy scripts
│
├── *.xml                            # VM XML reference examples
│   ├── win11-working-lookingglass-12700kf.xml  # Intel best practices
│   ├── win11-working-lookingglass-7950x3d.xml  # AMD 3D V-Cache
│   └── ...
│
├── setup.sh                         # Main setup script (wrapper)
├── fix_nvram.sh                     # NVRAM permission quick fix
├── .gitignore                       # Git ignore rules
└── README.md                        # This file
```

### Key Design Decisions

**Modular Ansible Tasks:**
- Each task file has a single, clear purpose (20-80 lines)
- Orchestrator pattern with `main.yml` coordinators
- Easy to debug, extend, and maintain
- No monolithic 200+ line files

**Minimal Sudo Philosophy:**
- Sudo only used for genuine requirements (dmidecode, package install)
- User directories for all generated files (`~/.local/share/vfio-setup/`)
- System files created as templates, manually installed by user

**Archive Directory:**
- Old/deprecated files moved to `archive/` instead of deletion
- Preserves git history and allows rollback if needed
- Clean separation between active and legacy code

## References

### Official Documentation

- [Looking Glass Official Site](https://looking-glass.io/)
- [Looking Glass Documentation](https://looking-glass.io/docs/)
- [VFIO Guide (Arch Wiki)](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [libvirt Hooks](https://libvirt.org/hooks.html)

### Community Resources

- [r/VFIO Subreddit](https://www.reddit.com/r/VFIO/)
- [Level1Techs Forums](https://forum.level1techs.com/c/software/vfio/...)
- [Looking Glass Discord](https://looking-glass.io/discord)

### Hardware Compatibility

- [IOMMU Groups Tool](https://github.com/clayfreeman/gpu-passthrough)
- [GPU Passthrough Wiki](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)

## Credits

- **Original Configuration**: @Pimaker
- **VFIO Scripts**: PixelQubed, RisingPrisum
- **Looking Glass**: Gnif (Geoffrey McRae)
- **Refactoring**: This modular organization

## License

This project is provided as-is for educational purposes. Individual components may have their own licenses.

## Support

For issues and questions:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review logs: `/var/log/libvirt/vfio.log`
3. Search [r/VFIO](https://www.reddit.com/r/VFIO/)
4. Ask in [Looking Glass Discord](https://looking-glass.io/discord)

---

**Note**: GPU passthrough requires careful configuration and may not work on all systems. Always backup your data before making system-level changes.
