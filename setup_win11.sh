#!/bin/bash
#############################################################################
##                  Complete Windows 11 VM Setup                           ##
##              One-Command Looking Glass Installation                     ##
#############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_NAME="${1:-win11}"
USE_ANSIBLE="${USE_ANSIBLE:-false}"
SKIP_ISO_DOWNLOAD="${SKIP_ISO_DOWNLOAD:-false}"

# Paths
ISO_DIR="/var/lib/libvirt/images"
WIN11_ISO="${ISO_DIR}/Win11_23H2.iso"
VIRTIO_ISO="${ISO_DIR}/virtio-win.iso"

#############################################################################
## Helper Functions
#############################################################################

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}$1${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Usage: sudo bash $0 [vm_name]"
        exit 1
    fi
}

#############################################################################
## Prerequisite Checks
#############################################################################

check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing_packages=()
    local missing_commands=()

    # Check commands
    for cmd in virsh qemu-img dmidecode lspci wget virt-manager; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_commands+=("$cmd")
        else
            print_success "$cmd found"
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        print_error "Missing required commands: ${missing_commands[*]}"
        print_info "Installing required packages..."
        apt update
        apt install -y qemu-kvm libvirt-daemon-system virtinst virt-manager \
                       ovmf dmidecode pciutils wget bridge-utils dnsmasq
    fi

    # Check IOMMU
    print_step "Checking IOMMU..."
    if dmesg | grep -qi "iommu.*enabled"; then
        print_success "IOMMU is enabled"
    else
        print_warn "IOMMU may not be enabled!"
        print_warn "Add 'intel_iommu=on' or 'amd_iommu=on' to kernel parameters"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Check libvirt
    print_step "Checking libvirt..."
    if systemctl is-active --quiet libvirtd; then
        print_success "libvirtd is running"
    else
        print_info "Starting libvirtd..."
        systemctl start libvirtd
        systemctl enable libvirtd
        print_success "libvirtd started"
    fi
}

#############################################################################
## Hardware Detection
#############################################################################

detect_hardware() {
    print_header "Detecting Hardware"

    # Detect GPU
    print_step "Detecting GPU..."
    local gpu_info=$(lspci -nn | grep -iE "vga|3d controller" | head -1)

    if [[ -z "$gpu_info" ]]; then
        print_error "No GPU detected!"
        exit 1
    fi

    GPU_PCI=$(echo "$gpu_info" | awk '{print $1}')
    GPU_VENDOR=$(echo "$gpu_info" | grep -iq nvidia && echo "NVIDIA" || echo "AMD")

    print_success "Found $GPU_VENDOR GPU at $GPU_PCI"
    echo "$gpu_info"

    # Detect CPU
    print_step "Detecting CPU..."
    CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}')
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
    CPU_CORES=$(lscpu | grep "^CPU(s):" | awk '{print $2}')

    print_success "CPU: $CPU_MODEL ($CPU_CORES cores)"
    print_info "Vendor: $CPU_VENDOR"
}

#############################################################################
## Download ISOs
#############################################################################

download_isos() {
    print_header "Downloading Required ISOs"

    # Create ISO directory
    mkdir -p "$ISO_DIR"

    # VirtIO drivers
    if [[ -f "$VIRTIO_ISO" ]]; then
        print_success "VirtIO ISO already exists"
    else
        print_step "Downloading VirtIO drivers..."
        wget -O "$VIRTIO_ISO" \
            "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" \
            || {
                print_error "Failed to download VirtIO drivers"
                exit 1
            }
        print_success "VirtIO drivers downloaded"
    fi

    # Windows 11 ISO
    if [[ "$SKIP_ISO_DOWNLOAD" == "true" ]] || [[ -f "$WIN11_ISO" ]]; then
        if [[ -f "$WIN11_ISO" ]]; then
            print_success "Windows 11 ISO already exists"
        else
            print_warn "Windows 11 ISO not found!"
            print_info "Please download Windows 11 ISO manually:"
            print_info "  1. Visit: https://www.microsoft.com/software-download/windows11"
            print_info "  2. Download ISO to: $WIN11_ISO"
            read -p "Press Enter when ISO is downloaded, or Ctrl+C to exit..."
        fi
    else
        print_warn "Windows 11 ISO must be downloaded manually"
        print_info "Visit: https://www.microsoft.com/software-download/windows11"
        print_info "Save to: $WIN11_ISO"
        read -p "Press Enter when ready to continue..."

        if [[ ! -f "$WIN11_ISO" ]]; then
            print_error "Windows 11 ISO not found at $WIN11_ISO"
            exit 1
        fi
    fi
}

#############################################################################
## Configure System
#############################################################################

configure_hugepages() {
    print_header "Configuring Hugepages"

    local vm_memory_gb=${VM_MEMORY_GB:-16}
    local hugepages_count=$((vm_memory_gb * 1024 / 2))

    print_step "Setting up ${hugepages_count} hugepages for ${vm_memory_gb}GB VM..."

    echo "$hugepages_count" > /proc/sys/vm/nr_hugepages

    # Make persistent
    if ! grep -q "vm.nr_hugepages" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.nr_hugepages = $hugepages_count" >> /etc/sysctl.conf
        print_success "Hugepages configured (persistent)"
    else
        sed -i "s/vm.nr_hugepages.*/vm.nr_hugepages = $hugepages_count/" /etc/sysctl.conf
        print_success "Hugepages updated"
    fi

    # Verify
    local actual=$(cat /proc/sys/vm/nr_hugepages)
    if [[ "$actual" -eq "$hugepages_count" ]]; then
        print_success "Hugepages allocated: $actual"
    else
        print_warn "Hugepages requested: $hugepages_count, got: $actual"
    fi
}

#############################################################################
## Generate VM Configuration
#############################################################################

generate_vm() {
    print_header "Generating VM Configuration"

    if [[ "$USE_ANSIBLE" == "true" ]]; then
        print_step "Using Ansible for deployment..."

        cd "$SCRIPT_DIR/ansible"

        # Check if inventory exists
        if [[ ! -f "inventory.yml" ]]; then
            print_error "inventory.yml not found!"
            exit 1
        fi

        # Run playbook
        print_info "Running Ansible playbook..."
        ansible-playbook -i inventory.yml playbook.yml

        VM_XML="/usr/local/share/vfio-setup/${VM_NAME}.xml"
    else
        print_step "Using standalone setup script..."

        # Run setup script
        bash "$SCRIPT_DIR/scripts/setup-windows-vm.sh" "$VM_NAME"

        VM_XML="$SCRIPT_DIR/scripts/${VM_NAME}-generated.xml"
    fi

    print_success "VM configuration generated"
}

#############################################################################
## Update VM XML with ISOs
#############################################################################

update_xml_with_isos() {
    print_header "Configuring Boot ISOs"

    print_step "Adding Windows 11 ISO to VM configuration..."

    # Check if ISO paths are already in XML
    if grep -q "$WIN11_ISO" "$VM_XML"; then
        print_success "Windows ISO already configured"
    else
        # Find the Windows ISO cdrom device and add source
        sed -i "/<disk type='file' device='cdrom'>/,/<\/disk>/ {
            /<target dev='sdb'/,/<\/disk>/ {
                /<driver name='qemu'/a\      <source file='$WIN11_ISO'/>
            }
        }" "$VM_XML"
        print_success "Windows ISO configured"
    fi

    # Verify VirtIO ISO is present
    if grep -q "$VIRTIO_ISO" "$VM_XML"; then
        print_success "VirtIO ISO already configured"
    else
        print_warn "VirtIO ISO may need manual configuration"
    fi
}

#############################################################################
## Define and Prepare VM
#############################################################################

define_vm() {
    print_header "Defining VM in libvirt"

    # Check if VM already exists
    if virsh list --all | grep -q "$VM_NAME"; then
        print_warn "VM '$VM_NAME' already exists!"
        read -p "Undefine and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            virsh destroy "$VM_NAME" 2>/dev/null || true
            virsh undefine "$VM_NAME" --nvram 2>/dev/null || true
            print_info "Existing VM removed"
        else
            print_info "Skipping VM definition"
            return
        fi
    fi

    print_step "Defining VM..."
    virsh define "$VM_XML"
    print_success "VM '$VM_NAME' defined"

    # Verify
    if virsh list --all | grep -q "$VM_NAME"; then
        print_success "VM verified in libvirt"
    else
        print_error "VM definition failed!"
        exit 1
    fi
}

#############################################################################
## Start VM
#############################################################################

start_vm() {
    print_header "Starting VM"

    read -p "Start VM now? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_step "Starting $VM_NAME..."
        virsh start "$VM_NAME"
        print_success "VM started"

        sleep 2

        print_info "Launching virt-manager..."
        sudo -u "${SUDO_USER:-$USER}" DISPLAY="${DISPLAY:-:0}" virt-manager &

        print_success "Connect to VM in virt-manager to install Windows"
    else
        print_info "Skipped VM startup"
    fi
}

#############################################################################
## Post-Installation Instructions
#############################################################################

show_next_steps() {
    print_header "Setup Complete!"

    cat << EOF
${GREEN}╔════════════════════════════════════════════════════════════╗
║                 VM SETUP SUCCESSFUL!                       ║
╚════════════════════════════════════════════════════════════╝${NC}

${CYAN}VM Details:${NC}
  Name:       ${VM_NAME}
  Status:     $(virsh list --all | grep "$VM_NAME" | awk '{print $3}')
  XML:        ${VM_XML}

${CYAN}Next Steps:${NC}

${YELLOW}1. Install Windows 11${NC}
   - Connect with: virt-manager
   - During install, click "Load driver"
   - Browse to D:\\ (VirtIO ISO)
   - Install: viostor (storage) and NetKVM (network)
   - Complete Windows installation

${YELLOW}2. Install Drivers in Windows${NC}
   - Install GPU drivers (NVIDIA/AMD from their website)
   - Reboot Windows

${YELLOW}3. Install Looking Glass Host (in Windows)${NC}
   - Download from: https://looking-glass.io/downloads
   - Run: looking-glass-host-setup.exe
   - ✓ CHECK "Install as Windows Service"
   - Install IVSHMEM driver from Looking Glass package
   - Reboot Windows

${YELLOW}4. Install Looking Glass Client (on Linux)${NC}
   ${CYAN}sudo apt install looking-glass-client${NC}

${YELLOW}5. Run Looking Glass${NC}
   ${CYAN}virsh start ${VM_NAME}${NC}
   ${CYAN}looking-glass-client -F${NC}

${CYAN}Quick Commands:${NC}
  Start VM:       virsh start ${VM_NAME}
  Stop VM:        virsh shutdown ${VM_NAME}
  Force stop:     virsh destroy ${VM_NAME}
  Edit VM:        virsh edit ${VM_NAME}
  View XML:       virsh dumpxml ${VM_NAME}
  Connect GUI:    virt-manager
  Looking Glass:  looking-glass-client -F

${CYAN}Documentation:${NC}
  Full guide:     ${SCRIPT_DIR}/README.md
  VM evasion:     ${SCRIPT_DIR}/docs/VM_DETECTION_EVASION.md
  Wendell method: ${SCRIPT_DIR}/docs/WENDELL_METHOD.md
  Windows guide:  ${SCRIPT_DIR}/docs/WINDOWS_INSTALLATION_GUIDE.md

${GREEN}╔════════════════════════════════════════════════════════════╗
║  Your Windows 11 VM is ready with full VM detection       ║
║  evasion enabled for anti-cheat compatibility!             ║
╚════════════════════════════════════════════════════════════╝${NC}

EOF
}

#############################################################################
## Main Execution
#############################################################################

main() {
    print_header "Looking Glass Windows 11 VM Setup"

    check_root
    check_prerequisites
    detect_hardware
    download_isos
    configure_hugepages
    generate_vm
    update_xml_with_isos
    define_vm
    start_vm
    show_next_steps
}

# Handle arguments
case "${1:-}" in
    --help|-h)
        cat << EOF
Usage: sudo bash $0 [VM_NAME] [OPTIONS]

Arguments:
  VM_NAME                  Name for the VM (default: win11)

Environment Variables:
  USE_ANSIBLE=true         Use Ansible deployment method
  SKIP_ISO_DOWNLOAD=true   Skip Windows ISO download prompt
  VM_MEMORY_GB=16          VM memory in GB (default: 16)

Examples:
  sudo bash $0 win11
  sudo USE_ANSIBLE=true bash $0 gaming-vm
  sudo VM_MEMORY_GB=32 bash $0 win11

EOF
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
