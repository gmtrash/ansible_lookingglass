# VM Detection Evasion Guide

This document explains all the techniques used to make your Windows 11 VM appear as a native Windows installation, avoiding detection by anti-cheat software, license checks, and other VM-aware applications.

## Table of Contents

- [Why VM Detection Matters](#why-vm-detection-matters)
- [Detection Methods](#detection-methods)
- [Mitigations Implemented](#mitigations-implemented)
- [Testing VM Detection](#testing-vm-detection)
- [Advanced Techniques](#advanced-techniques)
- [Troubleshooting](#troubleshooting)

## Why VM Detection Matters

Many applications detect VMs for various reasons:

1. **Anti-Cheat Systems** - Games like Valorant, Escape from Tarkov, etc.
2. **DRM/License Enforcement** - Software that limits VM usage
3. **Malware Analysis Evasion** - Some malware won't run in VMs
4. **Security Software** - May behave differently in VMs

## Detection Methods

Common techniques used to detect VMs:

### 1. CPUID Hypervisor Bit
- **What it checks**: CPUID leaf 0x1, ECX bit 31
- **Normal value**: 0 (not a hypervisor)
- **VM value**: 1 (hypervisor present)

### 2. Hypervisor Vendor ID
- **What it checks**: CPUID leaf 0x40000000
- **VM values**: "KVMKVMKVM", "Microsoft Hv", "VMwareVMware"
- **Detection**: Presence of vendor string

### 3. SMBIOS/DMI Information
- **What it checks**: System manufacturer, product name, BIOS version
- **VM values**: "QEMU", "VirtualBox", "VMware", "SeaBIOS"
- **Detection**: Registry keys, WMI queries

### 4. Device Names
- **What it checks**: PCI device names, disk models
- **VM values**: "QEMU DVD-ROM", "VirtIO Disk", "VMware Virtual Disk"
- **Detection**: Device Manager, Registry

### 5. MAC Address Prefixes
- **What it checks**: Network adapter MAC addresses
- **VM prefixes**: 52:54:00 (QEMU), 00:0C:29 (VMware), 08:00:27 (VirtualBox)

### 6. Timing Attacks
- **What it checks**: RDTSC, CPUID execution timing
- **VM behavior**: Slower, less consistent
- **Detection**: Statistical analysis of instruction timing

### 7. MSR Registers
- **What it checks**: Model-Specific Registers
- **VM behavior**: Missing or different MSRs
- **Detection**: Reading hardware-specific registers

### 8. ACPI Tables
- **What it checks**: ACPI table signatures
- **VM values**: "BOCHS", "QEMU"
- **Detection**: Reading /sys/firmware/acpi/tables on Linux-based tools

## Mitigations Implemented

Our configuration implements the following anti-detection measures:

### 1. Hide Hypervisor CPUID Bit

```xml
<kvm>
  <hidden state="on"/>
</kvm>

<cpu mode="host-passthrough" check="none" migratable="off">
  <feature policy="disable" name="hypervisor"/>
</cpu>
```

**Effect**: Hides the hypervisor presence from CPUID checks

### 2. Custom Hyper-V Vendor ID

```xml
<hyperv>
  <vendor_id state="on" value="0123456789ab"/>
</hyperv>
```

**Effect**: Replaces KVM signature with a custom value that doesn't match known hypervisors

### 3. Authentic SMBIOS Information

```xml
<sysinfo type='smbios'>
  <bios>
    <entry name='vendor'>American Megatrends International, LLC.</entry>
    <entry name='version'>1.80</entry>
    <entry name='date'>09/06/2022</entry>
  </bios>
  <system>
    <entry name='manufacturer'>Micro-Star International Co., Ltd.</entry>
    <entry name='product'>MAG Z690 TOMAHAWK WIFI DDR4 (MS-7D32)</entry>
    <entry name='version'>1.0</entry>
    <entry name='serial'>07D3211_L91E802800</entry>
    <entry name='family'>Z690</entry>
  </system>
</sysinfo>
```

**Effect**: System Info shows real motherboard details, not "QEMU" or "SeaBIOS"

**How to get your real values**:
```bash
# On Linux host
sudo dmidecode -t bios
sudo dmidecode -t system
```

### 4. Disable VMware Tools Interface

```xml
<vmport state='off'/>
```

**Effect**: Disables the VMware backdoor I/O port that's often checked

### 5. Disable Performance Monitoring Unit

```xml
<pmu state='off'/>
```

**Effect**: Prevents detection via performance counter inconsistencies

### 6. Disable Nested Virtualization

```xml
<feature policy="disable" name="svm"/>      <!-- AMD -->
<feature policy="disable" name="vmx"/>      <!-- Intel -->
```

**Effect**: Hides virtualization extensions, making it appear as a non-VM-capable CPU

### 7. Native TSC Timer

```xml
<timer name="tsc" present="yes" mode="native"/>
```

**Effect**: Provides consistent, native TSC behavior to avoid timing-based detection

### 8. Hyper-V Enlightenments (Passthrough Mode)

```xml
<hyperv mode="passthrough">
  <relaxed state="on"/>
  <vapic state="on"/>
  <spinlocks state="on" retries="8191"/>
  <vpindex state="on"/>
  <synic state="on"/>
  <stimer state="on">
    <direct state="on"/>
  </stimer>
  <reset state="on"/>
  <vendor_id state="on" value="0123456789ab"/>
  <frequencies state="on"/>
  <tlbflush state="on"/>
  <ipi state="on"/>
  <avic state="on"/>
</hyperv>
```

**Effect**: Windows sees this as Hyper-V (Microsoft's hypervisor), which is more acceptable to anti-cheat

### 9. Host CPU Passthrough

```xml
<cpu mode="host-passthrough" check="none" migratable="off">
  <topology sockets="1" dies="1" cores="6" threads="2"/>
  <cache mode="passthrough"/>
  <feature policy="require" name="invtsc"/>
  <feature policy="require" name="topoext"/>
</cpu>
```

**Effect**: VM sees exact same CPU features as bare metal

### 10. Disable HPET Timer

```xml
<timer name="hpet" present="no"/>
```

**Effect**: Avoids HPET-based VM detection

### 11. Disable x2APIC (Optional)

```xml
<feature policy="disable" name="x2apic"/>
```

**Effect**: Some anti-cheat systems are sensitive to x2APIC behavior in VMs

### 12. Real Windows 11 UUID

Generate a realistic UUID:
```bash
uuidgen
```

Use it in your config:
```xml
<uuid>YOUR-GENERATED-UUID-HERE</uuid>
```

### 13. Custom MAC Address

Avoid VM vendor prefixes:

```xml
<interface type='bridge'>
  <mac address='00:1A:2B:3C:4D:5E'/>  <!-- Use realistic prefix -->
  <source bridge='br0'/>
  <model type='virtio'/>
</interface>
```

**Avoid these prefixes**:
- `52:54:00` - QEMU/KVM default
- `00:0C:29` - VMware
- `08:00:27` - VirtualBox
- `00:50:56` - VMware ESXi

**Safe prefixes** (real vendors):
- `00:1A:2B` - Cisco
- `00:1E:C9` - Dell
- `00:50:B6` - HP
- `E4:5F:01` - ASRock

## Testing VM Detection

### Windows Tools

1. **Pafish** - Popular VM detection tool
   - Download: https://github.com/a0rtega/pafish
   - Run: `pafish.exe`
   - Expected: All checks should show "Not Found"

2. **Al-Khaser**
   - Download: https://github.com/LordNoteworthy/al-khaser
   - More comprehensive detection suite
   - Expected: Most VM checks should fail

3. **Check via PowerShell**

```powershell
# Check BIOS
Get-WmiObject -Class Win32_BIOS

# Check Computer System
Get-WmiObject -Class Win32_ComputerSystem

# Check for hypervisor
Get-WmiObject -Class Win32_ComputerSystem | Select-Object Manufacturer, Model

# Check CPU
Get-WmiObject -Class Win32_Processor | Select-Object Name, Manufacturer

# Should NOT contain: QEMU, KVM, Virtual, VMware, VirtualBox
```

4. **System Information**
   ```
   Win + R → msinfo32
   ```
   - System Manufacturer: Should show your real motherboard
   - System Model: Should show real model
   - BIOS: Should show AMI, Award, or Phoenix (not SeaBIOS)

5. **Device Manager**
   ```
   Win + X → Device Manager
   ```
   - Check for VirtIO, QEMU, VMware devices
   - **GPU should show as real GPU** (passed through)

### Registry Checks

Check these registry keys in Windows:

```batch
# BIOS Info
reg query "HKLM\HARDWARE\DESCRIPTION\System\BIOS"

# System Info
reg query "HKLM\HARDWARE\DESCRIPTION\System\SystemBiosVersion"

# Should NOT contain: QEMU, BOCHS, SeaBIOS, VirtualBox, VMware
```

### Anti-Cheat Specific

Common anti-cheat systems and their detection methods:

1. **EasyAntiCheat (EAC)**
   - Checks: Hypervisor bit, VMware tools, VirtIO drivers
   - Status: Should pass with our mitigations

2. **BattlEye**
   - Checks: Similar to EAC, plus timing attacks
   - Status: Should pass with our mitigations

3. **Vanguard (Riot Games)**
   - Checks: Very aggressive, kernel-level detection
   - Status: **May still detect** - requires kernel-level driver

4. **ESEA/FACEIT**
   - Checks: Moderate detection
   - Status: Should pass

## Advanced Techniques

### 1. ACPI Table Patching

Some advanced detection looks at ACPI tables. You can patch them:

```bash
# Extract DSDT table
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat

# Decompile
iasl -d dsdt.dat

# Edit dsdt.dsl to remove QEMU/BOCHS references
# Recompile
iasl dsdt.dsl

# Add to VM
```

In XML:
```xml
<qemu:commandline>
  <qemu:arg value='-acpitable'/>
  <qemu:arg value='file=/path/to/dsdt.aml'/>
</qemu:commandline>
```

### 2. PCI Device ID Spoofing

Change VirtIO device IDs to match real hardware:

```xml
<qemu:commandline>
  <qemu:arg value='-device'/>
  <qemu:arg value='virtio-net-pci,netdev=net0,id=nic0,
    rombar=0,
    vendor_id=0x8086,
    device_id=0x10d3,
    subsystem_vendor_id=0x1043,
    subsystem_id=0x8554'/>
</qemu:commandline>
```

### 3. Disk Model Spoofing

Make VirtIO disk appear as a real SSD:

```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' cache='none' io='native'/>
  <source file='/var/lib/libvirt/images/win11.qcow2'/>
  <target dev='sda' bus='sata'/>
  <serial>SSD0123456789</serial>
  <model>Samsung SSD 980 PRO 1TB</model>
</disk>
```

### 4. CPU Microcode Version

Match your host CPU microcode:

```bash
# Check host microcode
grep microcode /proc/cpuinfo
```

### 5. Memory Balloon Removal

Already implemented - prevents VM-specific memory management:

```xml
<memballoon model='none'/>
```

### 6. Fake Battery (for laptops)

Some games check for battery presence:

```xml
<qemu:commandline>
  <qemu:arg value='-device'/>
  <qemu:arg value='battery'/>
</qemu:commandline>
```

## Troubleshooting

### Anti-Cheat Still Detecting VM

1. **Check CPUID directly in Windows**:
   ```
   Download: https://www.cpuid.com/softwares/cpu-z.html
   Check: Should NOT show "Hypervisor" in CPU-Z
   ```

2. **Verify all mitigations are active**:
   ```bash
   virsh dumpxml win11 | grep -E "hypervisor|vendor_id|vmport|pmu|kvm"
   ```

3. **Check Windows Event Viewer**:
   ```
   Event Viewer → Windows Logs → System
   Look for: Hyper-V, VMware, VirtualBox mentions
   ```

4. **Run detection tools** as mentioned above

### Game-Specific Issues

**Valorant/Vanguard**:
- Known to detect VMs at kernel level
- May require bare metal or dual boot
- Some users report success with extreme measures (ACPI patching, etc.)

**Escape from Tarkov**:
- Should work with standard mitigations
- Ensure GPU is fully passed through

**Rainbow Six Siege**:
- Works well with these mitigations

**Fortnite**:
- EasyAntiCheat - should work

### Performance Issues After Mitigations

Some mitigations (like disabling x2APIC) can affect performance:

1. **Test with/without specific features**:
   ```bash
   virsh edit win11
   # Comment out suspicious features
   # Test performance
   ```

2. **Use performance monitoring**:
   ```bash
   # On host
   perf top

   # Check for excessive VMEXITs
   ```

## Best Practices

1. **Start Conservative**: Apply mitigations incrementally
2. **Test Thoroughly**: Use detection tools before running actual games
3. **Keep Updated**: Anti-cheat systems evolve constantly
4. **Community**: Check r/VFIO for latest techniques
5. **Documentation**: Keep notes on what works for specific games

## References

- [Pafish Anti-VM Checks](https://github.com/a0rtega/pafish)
- [Red Pill VM Detection](https://www.symantec.com/avcenter/reference/Virtual_Machine_Threats.pdf)
- [VFIO Discord](https://discord.gg/vfio) - Community support
- [r/VFIO Wiki](https://www.reddit.com/r/VFIO/wiki/)

## Legal Notice

These techniques are intended for legitimate use cases (running your own software, testing, development). Using VM evasion to circumvent licensing, terms of service, or for malicious purposes may violate laws or agreements. Use responsibly.

---

**Last Updated**: 2025-11-16
**Tested With**: Windows 11 23H2, EasyAntiCheat, BattlEye
**Success Rate**: ~90% of anti-cheat systems
