# Looking Glass VFIO - Architecture Documentation

## Design Philosophy

This project follows these principles:
- **Automation-first**: Minimize manual steps
- **Idempotent**: Safe to run multiple times
- **Modular**: Reusable components
- **Declarative**: Ansible over bash where possible
- **Self-documenting**: Clear file organization

## Project Structure

```
ansible_lookingglass/
├── setup.sh                      # Bootstrap: installs Ansible, runs main playbook
├── ansible/
│   ├── setup_complete.yml        # Main orchestration playbook (7 phases)
│   ├── playbook.yml              # Legacy: VM generation only (kept for compatibility)
│   ├── inventory.yml             # User configuration (optional, auto-detected if not set)
│   ├── tasks/                    # Modular task files
│   │   ├── prerequisites.yml     # Package installation, IOMMU checks
│   │   ├── detect_hardware.yml   # GPU, CPU, SMBIOS auto-detection
│   │   ├── download_isos.yml     # VirtIO and Windows ISO management
│   │   ├── configure_host.yml    # Hugepages, system tuning
│   │   ├── install_vfio.yml      # VFIO libraries and hooks installation
│   │   ├── create_vm.yml         # VM XML generation and libvirt definition
│   │   ├── start_vm.yml          # VM startup and virt-manager launch
│   │   └── show_instructions.yml # Post-installation guidance
│   └── templates/
│       ├── vm-config.xml.j2      # VM XML template with evasion techniques
│       └── vfio.conf.j2          # VFIO configuration template
├── scripts/
│   ├── setup-windows-vm.sh       # Standalone: bash-only VM creation (no Ansible)
│   ├── vfio-start                # Hook helper: prepare host for VM start
│   └── vfio-stop                 # Hook helper: restore host after VM stop
├── lib/
│   └── vfio-common.sh            # Shared bash functions for hooks and scripts
├── hooks/
│   └── qemu.new                  # Libvirt hook (auto GPU switching)
├── docs/
│   ├── VM_DETECTION_EVASION.md   # Anti-cheat techniques
│   ├── WENDELL_METHOD.md         # KVM hiding deep dive with CPUID analysis
│   ├── WINDOWS_INSTALLATION_GUIDE.md
│   └── ARCHITECTURE.md           # This file
└── README.md                     # User-facing documentation
```

## Execution Flow

### Recommended Path: Ansible (setup.sh)

```
User runs: sudo ./setup.sh
    ↓
setup.sh checks for Ansible
    ↓
setup.sh installs Ansible if missing
    ↓
setup.sh runs: ansible-playbook setup_complete.yml
    ↓
┌─────────────────────────────────────────────┐
│  setup_complete.yml (Main Orchestrator)     │
├─────────────────────────────────────────────┤
│  Phase 1: prerequisites.yml                 │
│    - apt/dnf install packages               │
│    - check IOMMU enabled                    │
│    - start libvirtd                         │
│    - add user to groups                     │
├─────────────────────────────────────────────┤
│  Phase 2: detect_hardware.yml               │
│    - lspci for GPU                          │
│    - dmidecode for SMBIOS                   │
│    - save to /tmp/vfio_detected_hardware.yml│
├─────────────────────────────────────────────┤
│  Phase 3: download_isos.yml                 │
│    - wget VirtIO drivers                    │
│    - prompt for Windows 11 ISO              │
├─────────────────────────────────────────────┤
│  Phase 4: configure_host.yml                │
│    - calculate hugepages                    │
│    - sysctl vm.nr_hugepages                 │
│    - mount hugetlbfs                        │
├─────────────────────────────────────────────┤
│  Phase 5: install_vfio.yml                  │
│    - copy lib/vfio-common.sh                │
│    - copy scripts/vfio-{start,stop}         │
│    - install hooks/qemu to /etc/libvirt/    │
├─────────────────────────────────────────────┤
│  Phase 6: create_vm.yml                     │
│    - load detected hardware                 │
│    - template vm-config.xml.j2              │
│    - inject detected SMBIOS                 │
│    - set hyperv vendor_id (GenuineIntel)    │
│    - virsh define                           │
├─────────────────────────────────────────────┤
│  Phase 7: start_vm.yml                      │
│    - virsh start                            │
│    - launch virt-manager                    │
├─────────────────────────────────────────────┤
│  show_instructions.yml                      │
│    - display post-install steps             │
│    - save summary to file                   │
└─────────────────────────────────────────────┘
```

### Alternative Path: Standalone Script

```
User runs: sudo scripts/setup-windows-vm.sh win11
    ↓
bash script (no Ansible dependency)
    ↓
- detect_gpu() using lspci
- detect_smbios() using dmidecode
- generate_vm_xml() using heredoc
- downloads VirtIO ISO
- creates qcow2 disk
- writes XML to scripts/win11-generated.xml
    ↓
User manually: virsh define + virsh start
```

## Key Design Decisions

### 1. Why Ansible-First?

**Before (bash-only):**
- ❌ Hard to make idempotent
- ❌ No state management
- ❌ Error handling complex
- ❌ Package installation OS-specific

**After (Ansible):**
- ✅ Built-in idempotency
- ✅ Declarative state
- ✅ Package module handles OS differences
- ✅ Better error reporting
- ✅ Can scale to multiple hosts

### 2. Why Keep Bash Scripts?

The `scripts/setup-windows-vm.sh` standalone script serves two purposes:

1. **Fallback**: Works without Ansible
2. **Portability**: Can be used independently for quick testing
3. **Education**: Shows how it works under the hood

### 3. Modular Task Files

**Why separate task files instead of one huge playbook?**

- **Maintainability**: Each phase is ~50-100 lines
- **Reusability**: Can import specific phases
- **Debugging**: Easy to comment out phases
- **Testing**: Can test individual phases

### 4. Hardware Auto-Detection

**Why auto-detect vs manual configuration?**

```yaml
# Manual (inventory.yml) - Optional
gpu_pci_video: "0000:06:00.0"
smbios_system_manufacturer: "ASUS"

# Auto-detected - Default
# detect_hardware.yml runs dmidecode/lspci
# Saves to /tmp/vfio_detected_hardware.yml
# create_vm.yml loads and uses detected values
```

**Benefits:**
- Zero configuration for first run
- Works on any hardware
- SMBIOS values match real hardware (better VM evasion)
- inventory.yml becomes override-only

## Data Flow

```
Hardware → detect_hardware.yml → /tmp/vfio_detected_hardware.yml
                                          ↓
                                  create_vm.yml loads vars
                                          ↓
                                  vm-config.xml.j2 template
                                          ↓
                                  /usr/local/share/vfio-setup/win11.xml
                                          ↓
                                  virsh define
```

## File Naming Conventions

- **Playbooks**: `*_complete.yml`, `playbook.yml`
- **Tasks**: `tasks/*.yml` (verb-noun format: `create_vm.yml`)
- **Templates**: `templates/*.j2` (Jinja2 suffix)
- **Scripts**: `scripts/*` (no extension for main, `.sh` for helpers)
- **Libraries**: `lib/*.sh` (sourced functions)

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `VM_NAME` | `win11` | VM identifier |
| `VM_MEMORY_GB` | `16` | RAM allocation |
| `VM_VCPUS` | `12` | CPU core count |
| `AUTO_START_VM` | `true` | Start after creation |
| `SKIP_ISO_DOWNLOAD` | `false` | Skip Windows ISO check |
| `WINDOWS_ISO` | `/var/lib/libvirt/images/Win11_23H2.iso` | ISO path |

## Idempotency Strategy

Each task is safe to rerun:

| Task | First Run | Second Run |
|------|-----------|------------|
| Install packages | Installs | Skips (already installed) |
| Download ISO | Downloads | Skips (file exists) |
| Create disk | Creates | Skips (file exists) |
| Define VM | Defines | Undefines old, redefines |
| Configure hugepages | Sets sysctl | Updates if changed |

## VM Detection Evasion

Implemented in `vm-config.xml.j2`:

```xml
<!-- Layer 1: CPUID Hiding -->
<feature policy='disable' name='hypervisor'/>  <!-- CPUID leaf 0x1, bit 31 -->
<kvm><hidden state='on'/></kvm>                <!-- Hide KVM signature -->

<!-- Layer 2: Hyper-V Spoofing -->
<hyperv mode='custom'>
  <vendor_id value='GenuineIntel'/>  <!-- CPUID leaf 0x40000000 -->
  <!-- 12+ enlightenments -->
</hyperv>

<!-- Layer 3: SMBIOS Spoofing -->
<sysinfo type='smbios'>
  <bios>...</bios>        <!-- Type 0: Real BIOS -->
  <system>...</system>    <!-- Type 1: Real motherboard -->
  <baseboard>...</baseboard>  <!-- Type 2: Real baseboard -->
</sysinfo>

<!-- Layer 4: Device Hiding -->
<vmport state='off'/>   <!-- No VMware backdoor -->
<pmu state='off'/>      <!-- No performance counters -->
<timer name='hpet' present='no'/>  <!-- No HPET -->
```

See `docs/WENDELL_METHOD.md` for technical deep dive including CPUID assembly analysis.

## Future Enhancements

Possible improvements:

- [ ] Multi-VM support (parallel VMs)
- [ ] GPU selection menu (if multiple GPUs)
- [ ] Looking Glass client auto-install
- [ ] Post-install Windows automation (PowerShell DSC)
- [ ] Prometheus metrics export
- [ ] Backup/restore VM snapshots

## Migration Guide

### From Old Architecture

**Old way (manual):**
```bash
# Edit inventory.yml manually with GPU address
vim ansible/inventory.yml
# Run playbook
ansible-playbook playbook.yml -K
# Manually create disk
qemu-img create ...
# Manually define VM
virsh define ...
```

**New way (automated):**
```bash
sudo ./setup.sh
# Done!
```

### Compatibility

- ✅ Old `inventory.yml` still works (overrides auto-detection)
- ✅ Old `playbook.yml` still works (VM generation only)
- ✅ Old `scripts/setup-windows-vm.sh` still works (standalone)
- ✅ New `setup.sh` wraps everything

## Troubleshooting

**setup.sh fails to install Ansible:**
- Install manually: `sudo apt install ansible` or `sudo dnf install ansible`

**Auto-detection fails:**
- Run standalone: `sudo scripts/setup-windows-vm.sh`
- Or manually set in `inventory.yml`

**VM doesn't start:**
```bash
# Check logs
sudo journalctl -u libvirtd -f
virsh list --all

# Verify XML
virsh dumpxml win11
```

**IOMMU not enabled:**
```bash
# Check
dmesg | grep -i iommu

# Enable (edit /etc/default/grub)
GRUB_CMDLINE_LINUX_DEFAULT="... intel_iommu=on iommu=pt"
sudo update-grub
reboot
```

## Contributing

When adding features:
1. Add new task file to `ansible/tasks/`
2. Import in `setup_complete.yml`
3. Update this ARCHITECTURE.md
4. Update README.md if user-facing

## References

- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [libvirt Domain XML](https://libvirt.org/formatdomain.html)
- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [Looking Glass Documentation](https://looking-glass.io/docs/)
