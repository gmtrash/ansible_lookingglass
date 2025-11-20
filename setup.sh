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

echo -e "${CYAN}[INFO]${NC} Starting automated setup..."
echo -e "${CYAN}[INFO]${NC} Sudo may be required for package installation and system config\n"

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Run the main playbook
# Note: Individual tasks will prompt for sudo password only when needed
# Use -K flag if you want to provide sudo password upfront
ansible-playbook setup_complete.yml "$@"
