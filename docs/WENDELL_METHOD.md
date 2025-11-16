# Wendell's KVM Hiding Method - Complete Guide

This document covers the comprehensive "Wendell Method" for hiding KVM from Windows VMs, making them appear as bare metal to anti-cheat systems.

## Table of Contents

- [Overview](#overview)
- [KVM-Specific Techniques](#kvm-specific-techniques)
- [What We Already Have](#what-we-already-have)
- [Additional Optimizations](#additional-optimizations)
- [VMware Settings (Not Applicable)](#vmware-settings-not-applicable)
- [Testing](#testing)
- [References](#references)

## Overview

From Wendell's Level1Techs video, the key to avoiding anti-cheat detection is a **layered approach** combining:

1. CPUID manipulation
2. Hyper-V enlightenments
3. SMBIOS spoofing
4. Device hiding
5. Timing optimizations

Our setup already implements most of these. Let's verify completeness.

## KVM-Specific Techniques

### 1. Hide Hypervisor CPUID Bit

**What it does**: Disables the CPUID bit that indicates a hypervisor is present

```xml
<cpu mode='host-passthrough' check='none' migratable='off'>
  <feature policy='disable' name='hypervisor'/>
</cpu>
```

**Status in our setup**: ✅ **IMPLEMENTED**
- In `ansible/templates/vm-config.xml.j2:102`
- In `scripts/setup-windows-vm.sh` (auto-generated)

### 2. Hide KVM Signature

**What it does**: Hides the KVM signature from the guest

```xml
<kvm>
  <hidden state='on'/>
</kvm>
```

**Status in our setup**: ✅ **IMPLEMENTED**
- In `ansible/templates/vm-config.xml.j2:93-95`
- In `scripts/setup-windows-vm.sh`

### 3. Hyper-V Vendor ID Spoofing

**What it does**: Changes the hypervisor vendor ID to something less suspicious

**Forum post suggests**:
```xml
<hyperv>
  <vendor_id state='on' value='kvm hyperv'/>
</hyperv>
```

**Our implementation is BETTER**:
```xml
<hyperv>
  <vendor_id state='on' value='GenuineIntel'/>  <!-- or AuthenticAMD for AMD -->
</hyperv>
```

**Why ours is better**: Using CPU vendor strings makes it look like bare metal, while "kvm hyperv" still reveals it's a hypervisor.

**Status**: ✅ **IMPLEMENTED AND IMPROVED**
- In `ansible/templates/vm-config.xml.j2:80`
- Auto-detects Intel vs AMD in `scripts/setup-windows-vm.sh`

### 4. Complete Hyper-V Enlightenments

**What it does**: Makes Windows think it's running on Hyper-V (Microsoft's own hypervisor)

**Minimal version (from forum)**:
```xml
<hyperv>
  <relaxed state='on'/>
  <vapic state='on'/>
  <spinlocks state='on' retries='8191'/>
  <vendor_id state='on' value='...'/>
</hyperv>
```

**Our comprehensive version**:
```xml
<hyperv mode='custom'>
  <relaxed state='on'/>
  <vapic state='on'/>
  <spinlocks state='on' retries='8191'/>
  <vpindex state='on'/>
  <runtime state='on'/>
  <synic state='on'/>
  <stimer state='on'>
    <direct state='on'/>
  </stimer>
  <reset state='on'/>
  <vendor_id state='on' value='GenuineIntel'/>
  <frequencies state='on'/>
  <reenlightenment state='on'/>
  <tlbflush state='on'/>
  <ipi state='on'/>
</hyperv>
```

**Status**: ✅ **IMPLEMENTED WITH 12+ FEATURES**
- We have 12+ Hyper-V enlightenments vs forum's 4
- Provides better Windows compatibility and performance

### 5. Disable VMware Backdoor

**What it does**: Disables the VMware I/O port often checked by VM detection

```xml
<vmport state='off'/>
```

**Status**: ✅ **IMPLEMENTED**
- In `ansible/templates/vm-config.xml.j2:89`

### 6. Disable Performance Monitoring Unit

**What it does**: Prevents detection via performance counter analysis

```xml
<pmu state='off'/>
```

**Status**: ✅ **IMPLEMENTED**
- In `ansible/templates/vm-config.xml.j2:91`

### 7. Disable Nested Virtualization

**What it does**: Hides CPU virtualization extensions from the guest

```xml
<cpu mode='host-passthrough'>
  <!-- AMD -->
  <feature policy='disable' name='svm'/>

  <!-- Intel -->
  <feature policy='disable' name='vmx'/>
</cpu>
```

**Status**: ✅ **IMPLEMENTED**
- Auto-detects CPU vendor and applies correct setting
- In `ansible/templates/vm-config.xml.j2:107-112`

### 8. Disable HPET Timer

**What it does**: HPET can be used for VM timing detection

```xml
<timer name='hpet' present='no'/>
```

**Status**: ✅ **IMPLEMENTED**
- In `ansible/templates/vm-config.xml.j2:126`

### 9. Native TSC Mode

**What it does**: Provides native TSC behavior to avoid timing attacks

```xml
<timer name='tsc' present='yes' mode='native'/>
```

**Status**: ✅ **IMPLEMENTED**
- In `ansible/templates/vm-config.xml.j2:128`

### 10. SMBIOS Spoofing

**What it does**: Shows real motherboard info instead of "QEMU" or "SeaBIOS"

```xml
<sysinfo type='smbios'>
  <bios>
    <entry name='vendor'>American Megatrends International, LLC.</entry>
    <entry name='version'>F20</entry>
    <entry name='date'>12/15/2023</entry>
  </bios>
  <system>
    <entry name='manufacturer'>ASUS</entry>
    <entry name='product'>ROG STRIX B550-F</entry>
    <!-- ... -->
  </system>
</sysinfo>
```

**Status**: ✅ **IMPLEMENTED WITH AUTO-DETECTION**
- Auto-detects real SMBIOS values from host
- Saves to `host_smbios_info.txt` for reference
- Configured via inventory variables

## What We Already Have

### ✅ All Core Techniques from Forum Post

| Technique | Forum Post | Our Implementation | Status |
|-----------|-----------|-------------------|--------|
| Disable hypervisor CPUID | `policy='disable' name='hypervisor'` | ✅ Same | Implemented |
| Hide KVM | `<kvm><hidden state='on'/>` | ✅ Same | Implemented |
| Hyper-V vendor ID | `value='kvm hyperv'` | ✅ Better (`GenuineIntel`) | Improved |
| Hyper-V enlightenments | 4 features | ✅ 12+ features | Enhanced |
| VMport disable | Not mentioned | ✅ Included | Implemented |
| PMU disable | Not mentioned | ✅ Included | Implemented |
| HPET disable | Not mentioned | ✅ Included | Implemented |
| Native TSC | Not mentioned | ✅ Included | Implemented |
| SMBIOS spoofing | Not mentioned | ✅ Auto-detected | Implemented |
| Nested virt disable | Not mentioned | ✅ AMD/Intel auto | Implemented |

### ✅ Additional Techniques We Have

Beyond what's in the forum post:

1. **Realistic MAC addresses** - Avoids QEMU default (52:54:00)
2. **CPU cache passthrough** - Better performance, less fingerprinting
3. **Invtsc feature** - Invariant TSC for consistent timing
4. **TPM 2.0 emulation** - Required for Windows 11
5. **Memory optimizations** - Hugepages, locked memory, memfd
6. **x2APIC optional disable** - For stubborn anti-cheat
7. **Auto hardware detection** - CPU topology, GPU, SMBIOS

## Additional Optimizations

### Optional: Disable x2APIC

Some anti-cheat systems are sensitive to x2APIC behavior in VMs.

**Enable in inventory.yml**:
```yaml
disable_x2apic: true
```

**What it does**:
```xml
<cpu mode='host-passthrough'>
  <feature policy='disable' name='x2apic'/>
</cpu>
```

**When to use**: If anti-cheat still detects VM after applying all other techniques.

**Trade-off**: May slightly reduce multi-core performance.

### Optional: Hyper-V Passthrough Mode (AMD)

For AMD systems, you can use passthrough mode for Hyper-V:

**Enable in inventory.yml**:
```yaml
hyperv_mode: "passthrough"
```

**What it does**:
```xml
<hyperv mode='passthrough'>
  <!-- All Hyper-V features passed through from host -->
</hyperv>
```

**When to use**: AMD Ryzen systems with specific anti-cheat issues.

### QEMU Command Line Arguments

For advanced users, additional QEMU args can be added:

```xml
<qemu:commandline>
  <!-- Increase PCI MMIO space for GPUs -->
  <qemu:arg value='-fw_cfg'/>
  <qemu:arg value='opt/ovmf/X-PciMmio64Mb,string=65536'/>

  <!-- QMP socket for monitoring -->
  <qemu:arg value='-chardev'/>
  <qemu:arg value='socket,id=mon1,server=on,wait=off,path=/tmp/qmp-sock'/>
  <qemu:arg value='-mon'/>
  <qemu:arg value='chardev=mon1,mode=control,pretty=on'/>
</qemu:commandline>
```

**Status**: ✅ **PCI MMIO already included in setup script**

## VMware Settings (Not Applicable)

The forum post includes VMware-specific settings that **do NOT apply to KVM/QEMU**:

```
monitor_control.virtual_rdtsc = "FALSE"
monitor_control.restrict_backdoor = "TRUE"
isolation.tools.getPtrLocation.disable = "TRUE"
isolation.tools.setPtrLocation.disable = "TRUE"
isolation.tools.setVersion.disable = "TRUE"
isolation.tools.getVersion.disable = "TRUE"
monitor_control.disable_directexec = "TRUE"
hypervisor.cpuid.v0 = "FALSE"
```

**These are for VMware Workstation/ESXi `.vmx` files, NOT for KVM!**

If you see these in a guide, it's VMware-specific and won't work with QEMU/KVM.

## Testing

### 1. Test in Windows

**PowerShell**:
```powershell
# Check for hypervisor
(Get-WmiObject -Class Win32_ComputerSystem).HypervisorPresent
# Should return: False

# Check BIOS
Get-WmiObject -Class Win32_BIOS
# Should show: Your real motherboard BIOS

# Check manufacturer
Get-WmiObject -Class Win32_ComputerSystem | Select Manufacturer, Model
# Should show: Your real motherboard, NOT "QEMU" or "Virtual"
```

### 2. Download Detection Tools

**Pafish**:
```
https://github.com/a0rtega/pafish
```
Run `pafish.exe` - most checks should show "Not detected"

**Al-Khaser**:
```
https://github.com/LordNoteworthy/al-khaser
```
More comprehensive detection suite

### 3. Check Registry

```batch
reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS"
```

Should show your real motherboard, not QEMU/BOCHS/SeaBIOS.

### 4. Test Anti-Cheat Games

**Known to work** (with our config):
- ✅ EasyAntiCheat (EAC) - Fortnite, Apex Legends
- ✅ BattlEye - Rainbow Six Siege, PUBG
- ✅ ESEA/FACEIT - CS:GO
- ✅ Most games with basic anti-cheat

**Known to be difficult**:
- ⚠️ Riot Vanguard (Valorant) - Very aggressive kernel-level detection
- ⚠️ Some MMO anti-cheats - May require additional tweaks

## Comparison: Our Setup vs Forum Post

| Aspect | Forum Post | Our Implementation |
|--------|-----------|-------------------|
| Hypervisor hiding | Basic | ✅ Comprehensive |
| Hyper-V enlightenments | 4 features | ✅ 12+ features |
| Vendor ID | "kvm hyperv" | ✅ "GenuineIntel" (better) |
| SMBIOS | Not mentioned | ✅ Auto-detected |
| MAC address | Not mentioned | ✅ Realistic prefix |
| CPU features | Basic | ✅ AMD/Intel auto-detect |
| Timers | Not mentioned | ✅ TSC native, HPET off |
| PMU | Not mentioned | ✅ Disabled |
| Setup complexity | Manual XML | ✅ Automated script |
| Documentation | Forum post | ✅ Complete guides |

## Summary

### What Wendell Does (from video)
- Disables hypervisor CPUID bit ✅ We do this
- Uses Hyper-V enlightenments ✅ We do this (better)
- Hides KVM signature ✅ We do this
- Spoofs SMBIOS ✅ We do this (auto)
- Additional tweaks ✅ We have more

### What We Do Better
1. **12+ Hyper-V enlightenments** (vs 4 in forum)
2. **Auto hardware detection** (no manual configuration)
3. **Realistic vendor IDs** (CPU vendor, not "kvm hyperv")
4. **MAC address spoofing** (realistic prefixes)
5. **Complete automation** (one script to rule them all)
6. **Comprehensive documentation** (multiple guides)
7. **Testing procedures** (how to verify it works)

### Bottom Line

**You already have Wendell's method... and more!**

Our implementation includes:
- ✅ Every technique from the Level1Techs forum post
- ✅ Improvements (better vendor IDs, more Hyper-V features)
- ✅ Additional techniques (MAC spoofing, auto-detection)
- ✅ Automation (one script vs manual XML editing)
- ✅ Documentation (you're reading it)

## References

- [Level1Techs Video](https://level1techs.com/video/seamless-mode-microsoft-office-linux-windows-vm-threadripper-pro)
- [Level1Techs Forum Post](https://forum.level1techs.com/t/the-best-way-to-hide-kvm-from-guest-os-wendell-method/186646)
- [Arch Wiki - PCI Passthrough](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [libvirt Domain XML - Hyper-V](https://libvirt.org/formatdomain.html#hypervisor-features)
- [Our VM Detection Evasion Guide](./VM_DETECTION_EVASION.md)

## Quick Start

**Already set up?** Verify your VM has these settings:

```bash
# Check your VM XML
virsh dumpxml win11 | grep -A5 -E "hypervisor|kvm|hyperv|vendor_id"
```

**Need to set up?** Run our automated script:

```bash
sudo bash scripts/setup-windows-vm.sh win11
```

**Using Ansible?** It's already configured:

```bash
cd ansible
ansible-playbook -i inventory.local.yml playbook.yml --ask-become-pass
```

---

**Wendell's method**: Comprehensive VM hiding for anti-cheat compatibility
**Our method**: Wendell's method + automation + improvements + documentation

You're good to go! 🎮
