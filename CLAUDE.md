# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an **Ansible-based automation system** for configuring GPU passthrough (VFIO) with Looking Glass on Linux hosts running Windows 11 VMs via QEMU/KVM/libvirt. The codebase follows a **"prerequisite checker" philosophy** rather than an installer - it validates system state and provides manual instructions instead of automatically making system-level changes requiring root access.

## Critical Design Principles

### 1. Minimal-Sudo Setup Philosophy
**Important**: This setup uses sudo **only when genuinely required**, avoiding unnecessary privilege escalation:

**Sudo IS used for**:
- Reading hardware information (`dmidecode` for SMBIOS data - requires root)
- Installing missing system packages (only if not already installed)

**Sudo is NOT used for**:
- Creating VM configuration files (user directories: `~/.local/share/vfio-setup/`)
- Generating VM XML (written to user-owned locations)
- Defining VMs in libvirt session mode (user-level virtualization)

**System-level files** (hooks, services) are created as **templates in user directories**, then you manually copy them to `/etc` with sudo. This gives you control over what system changes are made.

**sudo-rs compatibility**: No `-K` flag (password caching) is used, so interactive prompts work with both standard sudo and sudo-rs.

### 2. SMBIOS Date Format Requirement
**Critical**: libvirt's SMBIOS validation requires BIOS dates in `MM/DD/YY` format (2-digit year), not `MM/DD/YYYY`:

- System `dmidecode` returns 4-digit years (e.g., `12/15/2023`)
- Must be converted to 2-digit format (e.g., `12/15/23`) in `ansible/tasks/detect_hardware.yml:101`
- Current regex pattern: `bios_info.date | trim | regex_replace('/\\d\\d(\\d\\d)$', '/\\1')`
- Failing to convert causes: `error: Invalid BIOS 'date' format` during VM definition

**Fallback handling**: The template (`vm-config.xml.j2`) checks for "Unknown" strings and uses realistic fallback defaults if `dmidecode` fails to read the system BIOS information.

### 3. Idempotent Design
All Ansible tasks are designed to be safely re-runnable. The playbook detects existing configurations and only performs necessary actions.

## Running the Setup

### Quick Start
```bash
# Standard automated setup
./setup.sh

# Custom VM configuration
VM_NAME=gaming VM_MEMORY_GB=32 VM_VCPUS=16 ./setup.sh

# Skip auto-start (just create the VM)
AUTO_START_VM=false ./setup.sh

# Replace existing VM without prompting
AUTO_REPLACE_VM=true ./setup.sh
```

### Environment Variables
- `VM_NAME` - VM name (default: `win11`)
- `VM_MEMORY_GB` - RAM in GB (default: `16`)
- `VM_VCPUS` - CPU cores (default: `12`)
- `AUTO_REPLACE_VM` - Replace existing VM without prompt (default: `false`)
- `AUTO_START_VM` - Start VM after creation (default: `true`)
- `SKIP_ISO_DOWNLOAD` - Skip ISO download check (default: `false`)
- `WINDOWS_ISO` - Path to Windows 11 ISO

### Direct Ansible Execution
```bash
cd ansible
ansible-playbook setup_complete.yml

# With custom variables
VM_NAME=custom ansible-playbook setup_complete.yml
```

### NVRAM Permission Fix
Common issue after VM creation:
```bash
# Quick fix for permission errors
./fix_nvram.sh [VM_NAME]

# Or via Ansible
cd ansible
VM_NAME=win11 ansible-playbook fix_nvram.yml
```

## Architecture

### Ansible Playbook Flow
The main playbook (`ansible/setup_complete.yml`) runs **7 sequential phases**:

1. **Phase 0: User Preferences** - Storage location selection (`tasks/user_preferences.yml`)
2. **Phase 1: Prerequisites** - Package checks, IOMMU verification (`tasks/prerequisites.yml`)
3. **Phase 2: Hardware Detection** - GPU/CPU/SMBIOS detection (`tasks/detect_hardware.yml`)
4. **Phase 3: Download ISOs** - VirtIO drivers, Windows ISO (`tasks/download_isos.yml`)
5. **Phase 4: Host Configuration** - Hugepages recommendations (`tasks/configure_host.yml`)
6. **Phase 5: VFIO Setup** - Hook/script installation (`tasks/install_vfio.yml`)
7. **Phase 6: VM Creation** - XML generation and libvirt definition (`tasks/create_vm.yml`)
8. **Phase 7: VM Startup** - Start VM and launch virt-manager (`tasks/start_vm.yml`)

### Key Data Flow

**Hardware Detection** → **Template Variables** → **VM XML Generation** → **libvirt Definition**

1. `detect_hardware.yml` uses `dmidecode` and `lspci` to gather system info
2. Results saved to `/tmp/vfio_detected_hardware.yml`
3. `create_vm.yml` loads this file and passes vars to `templates/vm-config.xml.j2`
4. Generated XML written to `~/.local/share/vfio-setup/{vm_name}.xml`
5. VM defined with `virsh define`

### Libvirt Hook Architecture

The hook system enables **automatic GPU switching** when VMs start/stop:

```
libvirt → /etc/libvirt/hooks/qemu → vfio-start / vfio-stop scripts
                                  ↓
                          lib/vfio-common.sh (shared functions)
```

**Hook triggers**:
- `prepare/begin` → runs `scripts/vfio-start` (stops display manager, loads VFIO)
- `release/end` → runs `scripts/vfio-stop` (restarts display manager, unloads VFIO)

**Manual installation** (after setup creates template):
```bash
sudo cp ~/.local/share/vfio-setup/qemu.hook /etc/libvirt/hooks/qemu
sudo chmod 755 /etc/libvirt/hooks/qemu
sudo systemctl restart libvirtd
```

## VM XML Template (vm-config.xml.j2)

### Anti-Detection Features
The template includes extensive **VM detection evasion** for gaming/anti-cheat:

- **SMBIOS spoofing** - Uses real host BIOS/motherboard info
- **Hyper-V enlightenments** - Custom vendor_id, hidden KVM signatures
- **CPU feature masking** - Disables hypervisor CPUID flag
- **Timer configuration** - Native TSC, disabled HPET
- **Realistic MAC address** - Intel NIC prefix instead of QEMU default
- **TPM 2.0 emulation** - Required for Windows 11

### Critical XML Sections

**SMBIOS date handling** (uses detected hardware):
```xml
<entry name='date'>{{ smbios_bios_date | default('12/15/23') }}</entry>
```

**GPU passthrough** (PCI addresses from detection):
```xml
<hostdev mode='subsystem' type='pci' managed='yes'>
  <source>
    <address domain='{{ gpu_pci_video.split(":")[0] }}'
             bus='{{ gpu_pci_video.split(":")[1] }}' ... />
  </source>
</hostdev>
```

**Looking Glass shared memory**:
```xml
<shmem name='looking-glass'>
  <model type='ivshmem-plain'/>
  <size unit='M'>{{ looking_glass_size_mb | default(256) }}</size>
</shmem>
```

## Common Issues and Solutions

### 1. sudo-rs Authentication Errors
**Symptom**: `sudo-rs: interactive authentication is required`

**Cause**: Tasks with `become: true` are incompatible with sudo-rs password caching

**Solution**: All sudo tasks have been removed. If you encounter this, a task still has `become: true` - remove it and convert to manual instructions pattern.

### 2. Invalid BIOS Date Format
**Symptom**: `error: Invalid BIOS 'date' format` during VM definition

**Cause**: BIOS date has 4-digit year instead of 2-digit

**Solution**: Check `ansible/tasks/detect_hardware.yml:101` has the year conversion regex:
```yaml
smbios_bios_date: "{{ bios_info.date | trim | regex_replace('/\\d\\d(\\d\\d)$', '/\\1') }}"
```

### 3. NVRAM Permission Denied
**Symptom**: VM fails to start with `Permission denied` on NVRAM file

**Solution**:
```bash
./fix_nvram.sh [vm_name]
```

**Automatic fix**: Built into `create_vm.yml` and `start_vm.yml` - auto-detects and fixes on creation/start

### 4. Package Detection False Positives
**Issue**: Ubuntu uses `qemu-system-x86` binary, not `qemu-system-x86_64`

**Solution**: `prerequisites.yml` checks for both binary names:
```bash
if command -v qemu-system-x86_64 &>/dev/null || command -v qemu-system-x86 &>/dev/null; then
```

## File Locations

### User Directories (No Sudo Required)
- VM configs: `~/.local/share/vfio-setup/`
- VM disks/ISOs: `~/libvirt/images/` (or user-specified)
- Hook templates: `~/.local/share/vfio-setup/qemu.hook`
- Service templates: `~/.local/share/vfio-setup/libvirt-nosleep@.service`

### System Directories (Manual Installation Required)
- Libvirt hooks: `/etc/libvirt/hooks/qemu`
- Systemd services: `/etc/systemd/system/libvirt-nosleep@.service`
- NVRAM files (session): `~/.local/share/libvirt/qemu/nvram/`
- NVRAM files (system): `/var/lib/libvirt/qemu/nvram/`

## Development Guidelines

### When Modifying Ansible Tasks

1. **Never add `become: true`** - The codebase has been refactored to avoid all sudo requirements
2. **Check for package detection** - Support both Ubuntu (`qemu-system-x86`) and standard (`qemu-system-x86_64`) naming
3. **Test with sudo-rs** - Ensure compatibility with Rust sudo implementation
4. **Preserve idempotency** - All tasks should handle existing configurations gracefully
5. **Use user directories** - Store all generated files in `~/.local/share/vfio-setup/` or user-specified locations

### When Modifying Templates

1. **SMBIOS dates must be 2-digit years** - `MM/DD/YY` format only
2. **Test VM XML validation** - Use `virsh define` to validate before committing
3. **Preserve anti-detection features** - Don't remove CPUID masking, timer configs, or SMBIOS spoofing
4. **Document variable sources** - Note if vars come from hardware detection vs defaults

### When Modifying Shell Scripts

1. **Source vfio-common.sh** - Use shared logging and utility functions
2. **Log all operations** - Use `log_info`, `log_warn`, `log_error` from library
3. **Handle errors gracefully** - Scripts run automatically via hooks, must not fail catastrophically
4. **Support manual execution** - Scripts should work both from hooks and direct invocation

## Looking Glass Setup Notes

**Critical concept**: Looking Glass terminology is backwards from what you'd expect:

- **Windows (guest)** runs the Looking Glass **HOST** (captures display)
- **Linux (host)** runs the Looking Glass **CLIENT** (views display)

The shared memory region (`/dev/shm/looking-glass` or KVMFR module) is the bridge between them.

## VM Creation Test Command

After making changes, test the full VM creation flow:
```bash
# Delete test VM if exists
virsh destroy test-vm 2>/dev/null || true
virsh undefine test-vm --nvram 2>/dev/null || true

# Run setup with test configuration
VM_NAME=test-vm VM_MEMORY_GB=8 VM_VCPUS=4 AUTO_START_VM=false ./setup.sh

# Verify XML is valid
virsh dumpxml test-vm

# Clean up
virsh undefine test-vm --nvram
```
