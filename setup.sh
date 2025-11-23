#!/bin/bash
#############################################################################
##           Looking Glass VFIO Setup - Bootstrap Script                   ##
##                      Minimal Ansible Launcher                           ##
#############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Looking Glass VFIO Setup - Automated Installation     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Check for ansible
if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Ansible not found - installing..."
    echo -e "${YELLOW}[INFO]${NC} This requires sudo privileges\n"

    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt install -y ansible
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y ansible
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm ansible
    else
        echo -e "${YELLOW}[ERROR]${NC} Could not install Ansible automatically"
        echo "Please install Ansible manually:"
        echo "  Ubuntu/Debian: sudo apt install ansible"
        echo "  Fedora/RHEL:   sudo dnf install ansible"
        echo "  Arch:          sudo pacman -S ansible"
        exit 1
    fi
    echo -e "${GREEN}[OK]${NC} Ansible installed\n"
else
    echo -e "${GREEN}[OK]${NC} Ansible found\n"
fi

# Pre-check: Are required packages already installed?
# This check runs WITHOUT sudo to avoid unnecessary password prompts
echo -e "${CYAN}[INFO]${NC} Checking system prerequisites..."
PACKAGES_MISSING=false

if command -v dpkg &>/dev/null; then
    # Debian/Ubuntu package check
    for pkg in qemu-kvm libvirt-daemon-system libvirt-clients virt-manager ovmf; do
        if ! dpkg -l 2>/dev/null | grep -q "^ii  $pkg"; then
            PACKAGES_MISSING=true
            break
        fi
    done
elif command -v rpm &>/dev/null; then
    # Fedora/RHEL package check
    for pkg in qemu-kvm libvirt virt-install virt-manager edk2-ovmf; do
        if ! rpm -q $pkg &>/dev/null; then
            PACKAGES_MISSING=true
            break
        fi
    done
fi

if [ "$PACKAGES_MISSING" = false ]; then
    echo -e "${GREEN}[OK]${NC} All required packages already installed"
    echo -e "${CYAN}[INFO]${NC} Running without sudo requirements\n"
    export SKIP_PACKAGE_INSTALL=true
else
    echo -e "${YELLOW}[INFO]${NC} Some packages need installation"
    echo -e "${CYAN}[INFO]${NC} Sudo will be requested when needed\n"
    export SKIP_PACKAGE_INSTALL=false
fi

echo -e "${CYAN}[INFO]${NC} Starting automated setup...\n"

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Run the main playbook
# Note: No -K flag to support sudo-rs (Rust sudo implementation)
# Tasks will prompt for sudo password ONLY when:
#   - Packages need installation
#   - System configuration needs changes
#   - Hooks/services need setup
# If your system is already configured, no sudo prompts will occur.
ansible-playbook setup_complete.yml "$@"
