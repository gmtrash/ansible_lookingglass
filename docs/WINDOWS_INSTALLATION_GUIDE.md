# Windows 11 Installation Guide for VFIO

## Table of Contents

- [Overview](#overview)
- [Do I Need to Patch the ISO?](#do-i-need-to-patch-the-iso)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Installation Steps](#detailed-installation-steps)
- [VirtIO Drivers](#virtio-drivers)
- [Post-Installation](#post-installation)
- [Troubleshooting](#troubleshooting)

## Overview

This guide covers installing Windows 11 in a QEMU/KVM VM with GPU passthrough and full VM detection evasion.

## Do I Need to Patch the ISO?

**Short answer: NO**

You do **NOT** need to patch or modify the Windows 11 ISO. The Windows installation works normally in a VM. However, you need to understand a few things:

### What You DON'T Need to Do

❌ **Patch the ISO** - Windows installs as-is
❌ **Inject drivers into ISO** - Not necessary for modern setups
❌ **Modify Windows registry beforehand** - Done after installation
❌ **Crack or modify activation** - Normal Windows activation works
❌ **Use special Windows builds** - Official ISO works fine

### What You DO Need

✅ **VirtIO drivers ISO** - For disk and network drivers during installation
✅ **Proper VM XML configuration** - With VM detection evasion (handled by our script)
✅ **GPU drivers** - Install after Windows is up (NVIDIA/AMD from official sites)
✅ **Looking Glass host application** - Install after Windows setup
✅ **TPM 2.0 emulation** - For Windows 11 requirements (in XML)

## Prerequisites

### Downloads Required

1. **Windows 11 ISO** (choose one method):

   **Official Microsoft Download:**
   ```bash
   # Visit: https://www.microsoft.com/software-download/windows11
   # Download: Windows 11 (multi-edition ISO)
   ```

   **Direct Link (changes periodically):**
   ```bash
   # Check Microsoft's official download page for current link
   wget -O windows11.iso "https://software-download.microsoft.com/download/..."
   ```

2. **VirtIO Drivers** (auto-downloaded by setup script):
   ```bash
   wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
   ```

3. **Looking Glass** (install after Windows setup):
   - Visit: https://looking-glass.io/downloads
   - Download: Latest stable release (e.g., looking-glass-host-setup-B6.exe)

### System Requirements

- IOMMU enabled in BIOS
- GPU available for passthrough
- At least 16GB RAM (32GB+ recommended)
- 120GB+ free disk space
- CPU with virtualization support

## Quick Start

### 1. Run the Setup Script

```bash
# As root
sudo bash scripts/setup-windows-vm.sh win11

# With custom settings
sudo VM_MEMORY_GB=32 VM_VCPUS=16 VM_DISK_SIZE=250G \
  bash scripts/setup-windows-vm.sh win11
```

This script will:
- Auto-detect your GPU and hardware
- Generate VM XML with all evasion techniques
- Download VirtIO drivers
- Create disk image
- Configure SMBIOS with your real hardware info

### 2. Add Windows ISO to XML

Edit the generated XML file:
```bash
vim win11-generated.xml
```

Find this section:
```xml
<disk type='file' device='cdrom'>
  <driver name='qemu' type='raw'/>
  <!-- ADD THIS LINE: -->
  <source file='/path/to/windows11.iso'/>
  <target dev='sdb' bus='sata'/>
  <readonly/>
  <boot order='1'/>
</disk>
```

### 3. Configure Hugepages

```bash
# Calculate: (RAM_GB * 1024) / 2
# For 16GB VM:
echo 8192 > /proc/sys/vm/nr_hugepages

# Make permanent
echo "vm.nr_hugepages = 8192" >> /etc/sysctl.conf
```

### 4. Define and Start VM

```bash
virsh define win11-generated.xml
virsh start win11
virt-manager  # Or virt-viewer win11
```

## Detailed Installation Steps

### Phase 1: Windows Installation

1. **Boot from ISO**
   - VM will boot from Windows ISO
   - You'll see the Windows setup screen

2. **Load VirtIO Drivers**

   When you reach "Where do you want to install Windows?":

   a. You won't see any drives initially
   b. Click **"Load driver"**
   c. Click **"Browse"**
   d. Navigate to the **VirtIO CD (D: or E:)**
   e. Browse to: `D:\viostor\w11\amd64\`
   f. Select the **Red Hat VirtIO SCSI controller**
   g. Click **Next**

   Now you should see your drive!

3. **Continue Installation**
   - Select the drive
   - Click Next
   - Windows will install normally
   - VM will reboot several times

4. **Complete Windows Setup**
   - Set up user account
   - Configure privacy settings
   - Skip/minimize Microsoft account if desired

### Phase 2: Driver Installation

After Windows boots to desktop:

1. **Install VirtIO Guest Tools**

   In Windows VM:
   - Open File Explorer
   - Navigate to VirtIO CD (D: or E:)
   - Run `virtio-win-guest-tools.exe`
   - Install all components:
     - Balloon driver (memory management)
     - Network driver (ethernet)
     - SPICE agent (clipboard, etc.)
     - Serial driver
   - Reboot when prompted

2. **Install GPU Drivers**

   **For NVIDIA:**
   ```
   Download from: https://www.nvidia.com/drivers
   Install: GeForce Game Ready Driver
   Reboot
   ```

   **For AMD:**
   ```
   Download from: https://www.amd.com/en/support
   Install: AMD Software: Adrenalin Edition
   Reboot
   ```

3. **Verify GPU is Working**
   - Open Device Manager
   - Expand "Display adapters"
   - Should see your GPU (not "Microsoft Basic Display Adapter")
   - Check for any yellow warning icons

### Phase 3: Looking Glass Setup

1. **Install IVSHMEM Driver**

   - Download IVSHMEM driver from Looking Glass downloads
   - Extract the zip file
   - Open Device Manager (Win+X → Device Manager)
   - Expand "System devices"
   - Find **"PCI standard RAM Controller"**
   - Right-click → **Update driver**
   - **Browse my computer for drivers**
   - Navigate to extracted IVSHMEM driver folder
   - Install the driver
   - **Do NOT reboot yet**

2. **Install Looking Glass Host**

   - Run `looking-glass-host-setup-B6.exe`
   - Choose installation directory
   - **IMPORTANT**: Check **"Install as a Windows Service"**
   - Complete installation

3. **Configure Looking Glass**

   Create file: `C:\ProgramData\Looking Glass (host)\looking-glass-host.ini`

   ```ini
   [app]
   shmFile=looking-glass

   [capture]
   # NVIDIA cards: use DXGI
   # AMD cards: use D3D12
   captureAPI=DXGI

   # Performance settings
   throttleFPS=0

   [audio]
   enabled=true

   [spice]
   enabled=true
   ```

4. **Start the Service**

   **Option A: Reboot** (service auto-starts)

   **Option B: Manual start**
   - Win+R → `services.msc`
   - Find **"Looking Glass (host)"**
   - Right-click → **Start**
   - Set to **Automatic** startup

5. **Verify Looking Glass is Running**
   - Check system tray for Looking Glass icon
   - Or check in Task Manager → Services

### Phase 4: Optimize for Headless Operation

Once Looking Glass is working, you can disable the virtual video adapter:

1. **Shutdown the VM**
   ```bash
   virsh shutdown win11
   ```

2. **Edit the XML**
   ```bash
   virsh edit win11
   ```

   Change:
   ```xml
   <video>
     <model type='qxl' ram='65536' vram='65536'/>
   </video>
   ```

   To:
   ```xml
   <video>
     <model type='none'/>
   </video>
   ```

3. **Save and restart**
   ```bash
   virsh start win11
   ```

4. **Connect with Looking Glass**
   ```bash
   looking-glass-client -F
   ```

   You should now see Windows through Looking Glass with GPU acceleration!

## VirtIO Drivers

### What are VirtIO Drivers?

VirtIO is a virtualization standard for network and disk device drivers. It provides:
- Better performance than emulated hardware
- Lower CPU overhead
- Better I/O throughput

### Which Drivers Do I Need?

**During Windows Installation:**
- `viostor` - Storage (required to see disk)
- `NetKVM` - Network (optional but recommended)

**After Windows Installation:**
- `vioscsi` - SCSI driver
- `vioser` - Serial driver
- `Balloon` - Memory balloon driver
- `qemupciserial` - PCI serial driver
- `qxldod` - QXL display driver (if using QXL video)
- `pvpanic` - QEMU pvpanic device
- `vioinput` - Input driver
- `viorng` - VirtIO RNG driver
- `viofs` - VirtIO filesystem driver (for shared folders)
- `spice-guest-tools` - SPICE agent, drivers, and tools

### VirtIO Driver Locations on ISO

```
virtio-win.iso
├── viostor/         # Storage drivers
│   └── w11/amd64/   # Windows 11 64-bit
├── NetKVM/          # Network drivers
│   └── w11/amd64/
├── Balloon/         # Memory balloon
├── vioserial/       # Serial drivers
└── guest-agent/     # QEMU guest agent
```

### Installing All Drivers at Once

**Method 1: Run installer**
```
D:\virtio-win-guest-tools.exe
```

**Method 2: Device Manager**
1. Open Device Manager
2. For each unknown device:
   - Right-click → Update driver
   - Browse to VirtIO ISO
   - Let Windows search subdirectories
   - Install all found drivers

## Post-Installation

### Windows Optimizations

1. **Disable unnecessary visual effects**
   - Settings → System → About → Advanced system settings
   - Performance → Visual Effects → Adjust for best performance

2. **Disable Windows Search indexing** (optional)
   - Services → Windows Search → Disable

3. **Set power plan to High Performance**
   - Power Options → High Performance

4. **Disable hibernation** (frees disk space)
   ```cmd
   powercfg /h off
   ```

### VM Detection Testing

Test if Windows thinks it's a VM:

**PowerShell:**
```powershell
# Check BIOS
Get-WmiObject -Class Win32_BIOS

# Check Computer System
Get-WmiObject -Class Win32_ComputerSystem

# Check for hypervisor
(Get-WmiObject -Class Win32_ComputerSystem).HypervisorPresent

# Should return: False
```

**Registry Check:**
```cmd
reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS"
# Should show YOUR real motherboard, not QEMU/SeaBIOS
```

**Download detection tools:**
- [Pafish](https://github.com/a0rtega/pafish)
- [Al-Khaser](https://github.com/LordNoteworthy/al-khaser)

Run these and verify most VM checks fail (= good!).

### Performance Tuning

1. **CPU Governor** (on Linux host)
   ```bash
   sudo cpupower frequency-set -g performance
   ```

2. **IRQ Affinity**
   - Pin GPU IRQs to specific cores for better latency

3. **Looking Glass FPS**
   - In client config: `throttleFPS=0` for unlimited
   - Or set to your monitor refresh rate

## Troubleshooting

### Can't See Disk During Installation

**Problem:** Windows installer shows no drives

**Solution:**
1. Click "Load driver"
2. Browse to VirtIO ISO
3. Navigate to `viostor\w11\amd64`
4. Select the driver
5. Install

### Black Screen After Installing GPU Drivers

**Problem:** Windows won't boot after GPU driver install

**Solution:**
1. Boot into Safe Mode (F8 during boot)
2. Uninstall GPU drivers
3. Check GPU is properly passed through:
   ```bash
   lspci -nnk | grep -A3 VGA
   # Should show vfio-pci as driver
   ```
4. Verify GPU is isolated in IOMMU group
5. Try again with latest drivers

### Looking Glass Shows Black Screen

**Problem:** Client connects but shows black

**Solutions:**
1. Verify Looking Glass Host is running in Windows:
   ```
   Task Manager → Services → Looking Glass
   ```

2. Check shared memory on Linux:
   ```bash
   ls -lh /dev/shm/looking-glass
   # Should exist and be ~256MB
   ```

3. Verify IVSHMEM driver installed in Windows:
   ```
   Device Manager → System devices → "IVSHMEM Device"
   ```

4. Check Looking Glass logs:
   ```
   C:\ProgramData\Looking Glass (host)\looking-glass-host.txt
   ```

5. Restart the service:
   ```
   services.msc → Looking Glass → Restart
   ```

### Windows Activation Issues

**Problem:** Windows won't activate

**Solution:**
- Windows activation works normally in VMs
- Use your legitimate product key
- If previously activated on bare metal, you may need to:
  - Call Microsoft activation line
  - Explain you moved to new hardware
  - They usually approve it

### Anti-Cheat Detection

**Problem:** Game/app detects VM and won't run

**Solutions:**
1. Verify all VM evasion settings are applied
2. Check SMBIOS shows real hardware:
   ```powershell
   Get-WmiObject -Class Win32_BIOS
   ```

3. Test with detection tools (Pafish, Al-Khaser)

4. Try additional evasion:
   - Disable x2APIC in XML
   - Use `hyperv_mode='passthrough'` for AMD
   - Ensure MAC address isn't VM vendor prefix

5. Some anti-cheat may still detect:
   - Riot Vanguard (Valorant) - Very aggressive
   - Solution: Dual boot or bare metal

### VirtIO Network Not Working

**Problem:** No network connectivity

**Solution:**
1. Install NetKVM driver:
   ```
   Device Manager → Update driver → Browse VirtIO ISO
   Navigate to: NetKVM\w11\amd64
   ```

2. If still no network:
   - Check host bridge is up: `ip link show br0`
   - Verify VM network config in XML
   - Try switching to `network='default'` instead of bridge

### Poor Performance

**Problem:** Stuttering, low FPS

**Solutions:**
1. **Verify hugepages allocated:**
   ```bash
   cat /proc/sys/vm/nr_hugepages
   ```

2. **Check CPU pinning:**
   ```bash
   virsh vcpuinfo win11
   ```

3. **Verify GPU is passed through correctly:**
   ```bash
   lspci -nnk -s 01:00.0  # Use your GPU address
   ```

4. **Check MSI interrupts enabled** (in Windows):
   - Use MSI Utility tool
   - Enable MSI for GPU

5. **Disable compositing** in Looking Glass client:
   ```bash
   looking-glass-client -F -p 0
   ```

## Additional Resources

- [Looking Glass Documentation](https://looking-glass.io/docs/)
- [VFIO Guide (Arch Wiki)](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [r/VFIO Community](https://www.reddit.com/r/VFIO/)
- [Level1Techs Forums](https://forum.level1techs.com/c/software/vfio/)

## Summary

**You do NOT need to:**
- ❌ Patch the Windows ISO
- ❌ Use special Windows builds
- ❌ Inject drivers into the ISO

**You DO need to:**
- ✅ Have VirtIO drivers ISO available
- ✅ Load drivers during Windows installation
- ✅ Use proper VM XML with evasion settings
- ✅ Install GPU drivers after Windows boots
- ✅ Install Looking Glass host application
- ✅ Configure everything correctly

Follow this guide step-by-step, and you'll have a Windows 11 VM that:
- Looks like real hardware to Windows
- Has native GPU performance
- Works with Looking Glass for seamless display
- Passes most anti-cheat systems

Good luck!
