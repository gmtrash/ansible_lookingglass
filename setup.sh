#!/bin/bash
#############################################################################
##           Looking Glass VFIO Setup - Bootstrap Script                   ##
##                      Direct execution with Ansible                       ##
#############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Looking Glass VFIO Setup - Automated Installation     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Don't run as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}[ERROR]${NC} Don't run this script as root. Run as normal user - sudo will be used when needed."
    exit 1
fi

# Check for required commands
REQUIRED_CMDS=("virsh" "qemu-img" "virt-install" "dmidecode" "lspci")
MISSING_CMDS=()

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_CMDS+=("$cmd")
    fi
done

# Install missing packages if needed
if [ ${#MISSING_CMDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}[WARNING]${NC} Missing commands: ${MISSING_CMDS[*]}"
    read -p "Install missing packages now? (y/N): " INSTALL_PKGS
    if [[ $INSTALL_PKGS =~ ^[Yy]$ ]]; then
        sudo apt update
        sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst virt-manager ovmf bridge-utils dnsmasq dmidecode pciutils wget curl
        echo -e "${GREEN}[OK]${NC} Packages installed\n"
    else
        echo -e "${RED}[ERROR]${NC} Cannot continue without required packages"
        exit 1
    fi
else
    echo -e "${GREEN}[OK]${NC} All required packages installed\n"
fi

# Check for ansible-playbook
if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Ansible not found - installing..."
    if command -v apt &>/dev/null; then
        sudo apt install -y ansible
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y ansible
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm ansible
    else
        echo -e "${RED}[ERROR]${NC} Could not install Ansible automatically"
        exit 1
    fi
    echo -e "${GREEN}[OK]${NC} Ansible installed\n"
else
    echo -e "${GREEN}[OK]${NC} Ansible found\n"
fi

# Ensure user is in libvirt/kvm groups
CURRENT_GROUPS=$(groups)
NEEDS_GROUPS=false

if ! echo "$CURRENT_GROUPS" | grep -q "libvirt"; then
    NEEDS_GROUPS=true
fi
if ! echo "$CURRENT_GROUPS" | grep -q "kvm"; then
    NEEDS_GROUPS=true
fi

if [ "$NEEDS_GROUPS" = true ]; then
    echo -e "${YELLOW}[INFO]${NC} Adding user to libvirt and kvm groups..."
    sudo usermod -aG libvirt,kvm "$USER"
    echo -e "${GREEN}[OK]${NC} Groups added. You may need to log out and back in for changes to take effect.\n"
else
    echo -e "${GREEN}[OK]${NC} User already in libvirt and kvm groups\n"
fi

echo -e "${CYAN}[INFO]${NC} Starting automated setup...\n"

# Configure hugepages if needed (for 16GB VM = 8192 hugepages)
VM_MEMORY_GB=${VM_MEMORY_GB:-16}
HUGEPAGES_NEEDED=$(( VM_MEMORY_GB * 1024 / 2 ))
HUGEPAGES_CURRENT=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo "0")

if [ "$HUGEPAGES_CURRENT" -lt "$HUGEPAGES_NEEDED" ]; then
    echo -e "${YELLOW}[INFO]${NC} Configuring hugepages (need $HUGEPAGES_NEEDED, have $HUGEPAGES_CURRENT)..."
    sudo sysctl -w vm.nr_hugepages=$HUGEPAGES_NEEDED
    if ! grep -q "^vm.nr_hugepages" /etc/sysctl.conf 2>/dev/null; then
        echo "vm.nr_hugepages = $HUGEPAGES_NEEDED" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
    echo -e "${GREEN}[OK]${NC} Hugepages configured\n"
else
    echo -e "${GREEN}[OK]${NC} Hugepages already configured ($HUGEPAGES_CURRENT >= $HUGEPAGES_NEEDED)\n"
fi

# Ensure libvirtd is running
if ! systemctl is-active --quiet libvirtd; then
    echo -e "${YELLOW}[INFO]${NC} Starting libvirtd service..."
    sudo systemctl start libvirtd
    sudo systemctl enable libvirtd
    echo -e "${GREEN}[OK]${NC} libvirtd started\n"
else
    echo -e "${GREEN}[OK]${NC} libvirtd is running\n"
fi

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Run the main playbook (no become password needed - we handle sudo in bash)
export SKIP_PACKAGE_INSTALL=true
ansible-playbook setup_complete.yml "$@"
