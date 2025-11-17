#!/bin/bash
#############################################################################
##                  Windows VM Setup Script                                ##
##          Automated Windows 11 VM Creation with VM Evasion              ##
#############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="${1:-win11}"
VM_STORAGE_DIR="${VM_STORAGE_DIR:-/var/lib/libvirt/images}"
VM_DISK_SIZE="${VM_DISK_SIZE:-120G}"
VM_MEMORY_GB="${VM_MEMORY_GB:-16}"
VM_VCPUS="${VM_VCPUS:-12}"

# Files
XML_OUTPUT="${SCRIPT_DIR}/${VM_NAME}-generated.xml"
CONFIG_OUTPUT="${SCRIPT_DIR}/${VM_NAME}-config.txt"
VIRTIO_ISO="${VM_STORAGE_DIR}/virtio-win.iso"

#############################################################################
## Helper Functions
#############################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_dependencies() {
    local missing=()

    for cmd in virsh qemu-img dmidecode lspci wget; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing[*]}"
        print_info "Install with: apt install qemu-kvm libvirt-daemon-system dmidecode pciutils wget"
        exit 1
    fi
}

#############################################################################
## Hardware Detection
#############################################################################

detect_cpu_vendor() {
    local vendor=$(lscpu | grep "Vendor ID" | awk '{print $3}')
    if [[ "$vendor" == "GenuineIntel" ]]; then
        echo "Intel"
    elif [[ "$vendor" == "AuthenticAMD" ]]; then
        echo "AMD"
    else
        echo "Unknown"
    fi
}

detect_cpu_topology() {
    local sockets=$(lscpu | grep "Socket(s):" | awk '{print $2}')
    local cores=$(lscpu | grep "Core(s) per socket:" | awk '{print $4}')
    local threads=$(lscpu | grep "Thread(s) per core:" | awk '{print $4}')

    echo "${sockets}:${cores}:${threads}"
}

detect_gpu() {
    print_info "Detecting GPUs..."

    local gpu_info=$(lspci -nn | grep -E "VGA|3D controller")

    if [[ -z "$gpu_info" ]]; then
        print_error "No GPU detected"
        return 1
    fi

    echo "$gpu_info"

    # Find NVIDIA GPU
    local nvidia=$(echo "$gpu_info" | grep -i nvidia | head -1 | awk '{print $1}')
    if [[ -n "$nvidia" ]]; then
        echo "NVIDIA:$nvidia"
        return 0
    fi

    # Find AMD GPU
    local amd=$(echo "$gpu_info" | grep -i -E "AMD|ATI|Radeon" | head -1 | awk '{print $1}')
    if [[ -n "$amd" ]]; then
        echo "AMD:$amd"
        return 0
    fi

    return 1
}

get_pci_ids() {
    local pci_addr="$1"

    # Get video device
    local video_domain="0x$(echo $pci_addr | cut -d: -f1)"
    local video_bus="0x$(echo $pci_addr | cut -d: -f2)"
    local video_slot="0x$(echo $pci_addr | cut -d: -f3 | cut -d. -f1)"
    local video_func="0x$(echo $pci_addr | cut -d: -f3 | cut -d. -f2)"

    echo "${video_domain}:${video_bus}:${video_slot}:${video_func}"

    # Check for audio function
    local audio_addr="${pci_addr%.*}.1"
    if lspci -s "$audio_addr" &>/dev/null; then
        local audio_func="0x1"
        echo "${video_domain}:${video_bus}:${video_slot}:${audio_func}"
    fi
}

detect_smbios() {
    print_info "Detecting SMBIOS information..."

    # BIOS (Type 0)
    local bios_vendor=$(dmidecode -s bios-vendor 2>/dev/null || echo "American Megatrends International, LLC.")
    local bios_version=$(dmidecode -s bios-version 2>/dev/null || echo "F20")
    local bios_date=$(dmidecode -s bios-release-date 2>/dev/null || echo "12/15/2023")

    # System (Type 1)
    local system_manufacturer=$(dmidecode -s system-manufacturer 2>/dev/null || echo "ASUS")
    local system_product=$(dmidecode -s system-product-name 2>/dev/null || echo "System Product Name")
    local system_version=$(dmidecode -s system-version 2>/dev/null || echo "1.0")
    local system_serial=$(dmidecode -s system-serial-number 2>/dev/null || echo "System Serial Number")
    local system_uuid=$(dmidecode -s system-uuid 2>/dev/null || uuidgen)
    local system_family=$(dmidecode -s system-family 2>/dev/null || echo "Desktop")

    # Baseboard (Type 2)
    local baseboard_manufacturer=$(dmidecode -s baseboard-manufacturer 2>/dev/null || echo "${system_manufacturer}")
    local baseboard_product=$(dmidecode -s baseboard-product-name 2>/dev/null || echo "${system_product}")
    local baseboard_version=$(dmidecode -s baseboard-version 2>/dev/null || echo "Rev X.0x")
    local baseboard_serial=$(dmidecode -s baseboard-serial-number 2>/dev/null || echo "Default string")
    local baseboard_asset=$(dmidecode -s baseboard-asset-tag 2>/dev/null || echo "Default string")
    # Note: baseboard-location is not available via dmidecode -s, need to parse type 2 output
    local baseboard_location=$(dmidecode -t baseboard 2>/dev/null | grep -i "Location In Chassis" | cut -d: -f2 | xargs || echo "Default string")

    echo "BIOS_VENDOR=${bios_vendor}"
    echo "BIOS_VERSION=${bios_version}"
    echo "BIOS_DATE=${bios_date}"
    echo "SYSTEM_MANUFACTURER=${system_manufacturer}"
    echo "SYSTEM_PRODUCT=${system_product}"
    echo "SYSTEM_VERSION=${system_version}"
    echo "SYSTEM_SERIAL=${system_serial}"
    echo "SYSTEM_UUID=${system_uuid}"
    echo "SYSTEM_FAMILY=${system_family}"
    echo "BASEBOARD_MANUFACTURER=${baseboard_manufacturer}"
    echo "BASEBOARD_PRODUCT=${baseboard_product}"
    echo "BASEBOARD_VERSION=${baseboard_version}"
    echo "BASEBOARD_SERIAL=${baseboard_serial}"
    echo "BASEBOARD_ASSET=${baseboard_asset}"
    echo "BASEBOARD_LOCATION=${baseboard_location}"
}

generate_mac_address() {
    # Use Intel NIC prefix to avoid VM detection
    printf "00:1E:C9:%02X:%02X:%02X" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256))
}

#############################################################################
## VirtIO Drivers
#############################################################################

download_virtio_drivers() {
    if [[ -f "$VIRTIO_ISO" ]]; then
        print_info "VirtIO drivers already downloaded: $VIRTIO_ISO"
        return 0
    fi

    print_info "Downloading VirtIO drivers..."

    local virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

    wget -O "$VIRTIO_ISO" "$virtio_url" || {
        print_error "Failed to download VirtIO drivers"
        return 1
    }

    print_info "VirtIO drivers downloaded to: $VIRTIO_ISO"
}

#############################################################################
## Disk Creation
#############################################################################

create_disk_image() {
    local disk_path="${VM_STORAGE_DIR}/${VM_NAME}.qcow2"

    if [[ -f "$disk_path" ]]; then
        print_warn "Disk already exists: $disk_path"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using existing disk"
            echo "$disk_path"
            return 0
        fi
        rm -f "$disk_path"
    fi

    print_info "Creating disk image: $disk_path ($VM_DISK_SIZE)"
    qemu-img create -f qcow2 "$disk_path" "$VM_DISK_SIZE" || {
        print_error "Failed to create disk image"
        return 1
    }

    echo "$disk_path"
}

#############################################################################
## XML Generation
#############################################################################

generate_vm_xml() {
    local disk_path="$1"
    local gpu_vendor="$2"
    local gpu_pci="$3"
    local gpu_audio_pci="$4"

    # Parse SMBIOS
    eval "$(detect_smbios)"

    # CPU detection
    local cpu_vendor=$(detect_cpu_vendor)
    local topology=$(detect_cpu_topology)
    local cpu_sockets=$(echo $topology | cut -d: -f1)
    local cpu_cores=$(echo $topology | cut -d: -f2)
    local cpu_threads=$(echo $topology | cut -d: -f3)

    # Generate MAC
    local mac_address=$(generate_mac_address)

    # Parse GPU PCI addresses
    local gpu_domain=$(echo $gpu_pci | cut -d: -f1)
    local gpu_bus=$(echo $gpu_pci | cut -d: -f2)
    local gpu_slot=$(echo $gpu_pci | cut -d: -f3)
    local gpu_func=$(echo $gpu_pci | cut -d: -f4)

    local audio_domain=""
    local audio_bus=""
    local audio_slot=""
    local audio_func=""

    if [[ -n "$gpu_audio_pci" ]]; then
        audio_domain=$(echo $gpu_audio_pci | cut -d: -f1)
        audio_bus=$(echo $gpu_audio_pci | cut -d: -f2)
        audio_slot=$(echo $gpu_audio_pci | cut -d: -f3)
        audio_func=$(echo $gpu_audio_pci | cut -d: -f4)
    fi

    # Determine hyperv vendor_id
    local hyperv_vendor_id="GenuineIntel"
    if [[ "$cpu_vendor" == "AMD" ]]; then
        hyperv_vendor_id="AuthenticAMD"
    fi

    # Calculate hugepages
    local hugepages_count=$((VM_MEMORY_GB * 1024 / 2))

    cat > "$XML_OUTPUT" <<EOF
<domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
  <name>${VM_NAME}</name>
  <uuid>${SYSTEM_UUID}</uuid>
  <metadata>
    <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
      <libosinfo:os id="http://microsoft.com/win/11"/>
    </libosinfo:libosinfo>
  </metadata>

  <!-- Memory: ${VM_MEMORY_GB}GB -->
  <memory unit='KiB'>$((VM_MEMORY_GB * 1024 * 1024))</memory>
  <currentMemory unit='KiB'>$((VM_MEMORY_GB * 1024 * 1024))</currentMemory>

  <memoryBacking>
    <hugepages/>
    <nosharepages/>
    <locked/>
    <source type='memfd'/>
    <access mode='shared'/>
  </memoryBacking>

  <!-- CPU Configuration -->
  <vcpu placement='static'>${VM_VCPUS}</vcpu>
  <iothreads>1</iothreads>

  <cputune>
$(for ((i=0; i<VM_VCPUS; i++)); do
    echo "    <vcpupin vcpu='$i' cpuset='$i'/>"
done)
    <emulatorpin cpuset='$((VM_VCPUS))-$((VM_VCPUS + 3))'/>
    <iothreadpin iothread='1' cpuset='$((VM_VCPUS))-$((VM_VCPUS + 3))'/>
  </cputune>

  <!-- SMBIOS Information - Real hardware to avoid VM detection -->
  <sysinfo type='smbios'>
    <bios>
      <entry name='vendor'>${BIOS_VENDOR}</entry>
      <entry name='version'>${BIOS_VERSION}</entry>
      <entry name='date'>${BIOS_DATE}</entry>
    </bios>
    <system>
      <entry name='manufacturer'>${SYSTEM_MANUFACTURER}</entry>
      <entry name='product'>${SYSTEM_PRODUCT}</entry>
      <entry name='version'>${SYSTEM_VERSION}</entry>
      <entry name='serial'>${SYSTEM_SERIAL}</entry>
      <entry name='uuid'>${SYSTEM_UUID}</entry>
      <entry name='family'>${SYSTEM_FAMILY}</entry>
    </system>
    <baseboard>
      <entry name='manufacturer'>${BASEBOARD_MANUFACTURER}</entry>
      <entry name='product'>${BASEBOARD_PRODUCT}</entry>
      <entry name='version'>${BASEBOARD_VERSION}</entry>
      <entry name='serial'>${BASEBOARD_SERIAL}</entry>
      <entry name='asset'>${BASEBOARD_ASSET}</entry>
      <entry name='location'>${BASEBOARD_LOCATION}</entry>
    </baseboard>
  </sysinfo>

  <!-- Boot Configuration -->
  <os firmware='efi'>
    <type arch='x86_64' machine='pc-q35-8.1'>hvm</type>
    <boot dev='cdrom'/>
    <boot dev='hd'/>
    <bootmenu enable='yes' timeout='3000'/>
    <smbios mode='sysinfo'/>
  </os>

  <!-- Features - VM Detection Evasion -->
  <features>
    <acpi/>
    <apic/>
    <!-- Hyper-V Enlightenments - Makes Windows think it's Hyper-V -->
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
      <vendor_id state='on' value='${hyperv_vendor_id}'/>
      <frequencies state='on'/>
      <reenlightenment state='on'/>
      <tlbflush state='on'/>
      <ipi state='on'/>
    </hyperv>
    <!-- VM Detection Evasion -->
    <vmport state='off'/>
    <pmu state='off'/>
    <kvm>
      <hidden state='on'/>
    </kvm>
  </features>

  <!-- CPU Passthrough with VM Detection Evasion -->
  <cpu mode='host-passthrough' check='none' migratable='off'>
    <topology sockets='${cpu_sockets}' dies='1' cores='$((VM_VCPUS / cpu_threads))' threads='${cpu_threads}'/>
    <feature policy='disable' name='hypervisor'/>
    <feature policy='require' name='invtsc'/>
$(if [[ "$cpu_vendor" == "AMD" ]]; then
    echo "    <feature policy='require' name='topoext'/>"
    echo "    <feature policy='disable' name='svm'/>"
else
    echo "    <feature policy='disable' name='vmx'/>"
fi)
    <cache mode='passthrough'/>
  </cpu>

  <!-- Clock Configuration -->
  <clock offset='localtime'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
    <timer name='tsc' present='yes' mode='native'/>
    <timer name='hypervclock' present='yes'/>
  </clock>

  <!-- Power Management -->
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>

  <!-- Devices -->
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>

    <!-- Primary Disk -->
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='writeback' io='threads'/>
      <source file='${disk_path}'/>
      <target dev='sda' bus='sata'/>
      <boot order='2'/>
    </disk>

    <!-- Windows ISO (to be added manually) -->
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <target dev='sdb' bus='sata'/>
      <readonly/>
      <boot order='1'/>
    </disk>

    <!-- VirtIO Drivers ISO -->
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${VIRTIO_ISO}'/>
      <target dev='sdc' bus='sata'/>
      <readonly/>
    </disk>

    <!-- Controllers -->
    <controller type='usb' index='0' model='qemu-xhci' ports='15'>
      <address type='pci' domain='0x0000' bus='0x02' slot='0x00' function='0x0'/>
    </controller>
    <controller type='pci' index='0' model='pcie-root'/>
    <controller type='pci' index='1' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='1' port='0x10'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0' multifunction='on'/>
    </controller>
    <controller type='pci' index='2' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='2' port='0x11'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x1'/>
    </controller>
    <controller type='pci' index='3' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='3' port='0x12'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x2'/>
    </controller>
    <controller type='pci' index='4' model='pcie-root-port'>
      <model name='pcie-root-port'/>
      <target chassis='4' port='0x13'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x3'/>
    </controller>
    <controller type='sata' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x1f' function='0x2'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x03' slot='0x00' function='0x0'/>
    </controller>

    <!-- Network - Realistic MAC to avoid VM detection -->
    <interface type='network'>
      <mac address='${mac_address}'/>
      <source network='default'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x01' slot='0x00' function='0x0'/>
    </interface>

    <!-- SPICE Console -->
    <channel type='spicevmc'>
      <target type='virtio' name='com.redhat.spice.0'/>
      <address type='virtio-serial' controller='0' bus='0' port='1'/>
    </channel>

    <!-- Input Devices -->
    <input type='tablet' bus='usb'>
      <address type='usb' bus='0' port='1'/>
    </input>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>

    <!-- TPM for Windows 11 -->
    <tpm model='tpm-tis'>
      <backend type='emulator' version='2.0'/>
    </tpm>

    <!-- Graphics -->
    <graphics type='spice' autoport='yes'>
      <listen type='address'/>
      <image compression='off'/>
    </graphics>

    <!-- Audio -->
    <sound model='ich9'>
      <audio id='1'/>
    </sound>
    <audio id='1' type='spice'/>

    <!-- Video - QXL for installation, will switch to none after GPU passthrough -->
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1'/>
    </video>

    <!-- GPU Passthrough -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='${gpu_domain}' bus='${gpu_bus}' slot='${gpu_slot}' function='${gpu_func}'/>
      </source>
      <rom bar='off'/>
      <address type='pci' domain='0x0000' bus='0x05' slot='0x00' function='0x0'/>
    </hostdev>
$(if [[ -n "$audio_domain" ]]; then
    cat <<AUDIO
    <!-- GPU Audio -->
    <hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
        <address domain='${audio_domain}' bus='${audio_bus}' slot='${audio_slot}' function='${audio_func}'/>
      </source>
      <rom bar='off'/>
      <address type='pci' domain='0x0000' bus='0x06' slot='0x00' function='0x0'/>
    </hostdev>
AUDIO
fi)

    <!-- Looking Glass Shared Memory -->
    <shmem name='looking-glass'>
      <model type='ivshmem-plain'/>
      <size unit='M'>256</size>
      <address type='pci' domain='0x0000' bus='0x07' slot='0x00' function='0x0'/>
    </shmem>

    <!-- Disable Memory Ballooning -->
    <memballoon model='none'/>
  </devices>

  <!-- QEMU Command Line Arguments -->
  <qemu:commandline>
    <qemu:arg value='-fw_cfg'/>
    <qemu:arg value='opt/ovmf/X-PciMmio64Mb,string=65536'/>
  </qemu:commandline>
</domain>
EOF

    print_info "VM XML generated: $XML_OUTPUT"
}

#############################################################################
## Configuration Summary
#############################################################################

save_configuration() {
    local gpu_vendor="$1"
    local gpu_pci="$2"

    cat > "$CONFIG_OUTPUT" <<EOF
# Windows VM Configuration
# Generated: $(date)

VM_NAME=${VM_NAME}
VM_MEMORY_GB=${VM_MEMORY_GB}
VM_VCPUS=${VM_VCPUS}
VM_DISK_SIZE=${VM_DISK_SIZE}
VM_STORAGE_DIR=${VM_STORAGE_DIR}

GPU_VENDOR=${gpu_vendor}
GPU_PCI_ADDRESS=${gpu_pci}

# SMBIOS
$(detect_smbios)

# Hugepages needed: $((VM_MEMORY_GB * 1024 / 2))

# Next Steps:
# 1. Download Windows 11 ISO
# 2. Edit the XML and add Windows ISO path to the first CD-ROM device
# 3. Define the VM: virsh define ${XML_OUTPUT}
# 4. Start the VM: virsh start ${VM_NAME}
# 5. Connect with virt-manager or: virt-viewer ${VM_NAME}
# 6. Install Windows 11
# 7. Install GPU drivers in Windows
# 8. Install Looking Glass host in Windows
# 9. Switch video model to 'none' for headless GPU passthrough
EOF

    print_info "Configuration saved: $CONFIG_OUTPUT"
}

#############################################################################
## Main
#############################################################################

main() {
    print_header "Windows VM Setup Script"

    check_root
    check_dependencies

    print_info "VM Name: $VM_NAME"
    print_info "Memory: ${VM_MEMORY_GB}GB"
    print_info "vCPUs: $VM_VCPUS"
    print_info "Disk Size: $VM_DISK_SIZE"

    # Detect GPU
    print_header "GPU Detection"
    local gpu_detection=$(detect_gpu)
    local gpu_vendor=$(echo "$gpu_detection" | grep -E "NVIDIA|AMD" | cut -d: -f1)
    local gpu_pci_short=$(echo "$gpu_detection" | grep -E "NVIDIA|AMD" | cut -d: -f2)

    if [[ -z "$gpu_vendor" ]]; then
        print_error "No compatible GPU found"
        exit 1
    fi

    print_info "Found $gpu_vendor GPU at $gpu_pci_short"

    # Get full PCI IDs
    local pci_ids=($(get_pci_ids "$gpu_pci_short"))
    local gpu_pci="${pci_ids[0]}"
    local gpu_audio_pci="${pci_ids[1]:-}"

    print_info "GPU PCI: $gpu_pci"
    [[ -n "$gpu_audio_pci" ]] && print_info "Audio PCI: $gpu_audio_pci"

    # Download VirtIO drivers
    print_header "VirtIO Drivers"
    download_virtio_drivers

    # Create disk
    print_header "Disk Creation"
    local disk_path=$(create_disk_image)

    # Generate XML
    print_header "XML Generation"
    generate_vm_xml "$disk_path" "$gpu_vendor" "$gpu_pci" "$gpu_audio_pci"

    # Save configuration
    save_configuration "$gpu_vendor" "$gpu_pci_short"

    # Final instructions
    print_header "Setup Complete!"

    cat <<EOF

${GREEN}✓ VM XML generated: ${XML_OUTPUT}${NC}
${GREEN}✓ Disk created: ${disk_path}${NC}
${GREEN}✓ VirtIO drivers: ${VIRTIO_ISO}${NC}
${GREEN}✓ Configuration: ${CONFIG_OUTPUT}${NC}

${BLUE}Next Steps:${NC}

1. ${YELLOW}Download Windows 11 ISO${NC}
   wget https://software-download.microsoft.com/download/...

2. ${YELLOW}Edit the XML to add Windows ISO path${NC}
   Edit ${XML_OUTPUT}, find the first <disk device='cdrom'> and add:
   <source file='/path/to/windows11.iso'/>

3. ${YELLOW}Configure hugepages${NC}
   echo $((VM_MEMORY_GB * 1024 / 2)) > /proc/sys/vm/nr_hugepages

4. ${YELLOW}Define the VM${NC}
   virsh define ${XML_OUTPUT}

5. ${YELLOW}Start the VM${NC}
   virsh start ${VM_NAME}

6. ${YELLOW}Connect to VM${NC}
   virt-manager
   # Or: virt-viewer ${VM_NAME}

7. ${YELLOW}Install Windows 11${NC}
   - During installation, load VirtIO drivers for disk/network
   - Click "Load Driver" → Browse D:\\ (VirtIO ISO)
   - Install viostor (storage) and NetKVM (network)

8. ${YELLOW}After Windows installation:${NC}
   - Install GPU drivers (NVIDIA/AMD)
   - Install Looking Glass Host from https://looking-glass.io/downloads
   - Install IVSHMEM driver from Looking Glass package
   - Configure Looking Glass Host as a service

9. ${YELLOW}Switch to headless mode${NC}
   Edit XML and change:
   <video><model type='none'/></video>

   Redefine: virsh define ${XML_OUTPUT}

10. ${YELLOW}Install Looking Glass Client on Linux${NC}
    apt install looking-glass-client    # Ubuntu/Debian
    dnf install looking-glass-client    # Fedora

11. ${YELLOW}Run Looking Glass${NC}
    looking-glass-client -F

${BLUE}VM Detection Evasion:${NC}
${GREEN}✓${NC} SMBIOS spoofed with real hardware values
${GREEN}✓${NC} Hyper-V enlightenments configured
${GREEN}✓${NC} Hypervisor CPUID bit hidden
${GREEN}✓${NC} VMware backdoor disabled
${GREEN}✓${NC} Realistic MAC address generated
${GREEN}✓${NC} Native TSC timing
${GREEN}✓${NC} PMU disabled
${GREEN}✓${NC} HPET disabled
${GREEN}✓${NC} Nested virtualization hidden

${BLUE}For more information:${NC}
- Full documentation: ${SCRIPT_DIR}/README.md
- VM evasion guide: ${SCRIPT_DIR}/docs/VM_DETECTION_EVASION.md

EOF
}

main "$@"
