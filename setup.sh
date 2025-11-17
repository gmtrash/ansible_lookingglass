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

# Check root
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[WARN]${NC} This script needs sudo privileges"
    echo -e "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# Check for ansible
if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${GREEN}[SETUP]${NC} Installing Ansible..."

    if command -v apt &>/dev/null; then
        apt update
        apt install -y ansible
    elif command -v dnf &>/dev/null; then
        dnf install -y ansible
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm ansible
    else
        echo -e "${YELLOW}[ERROR]${NC} Could not install Ansible automatically"
        echo "Please install Ansible manually and re-run this script"
        exit 1
    fi
fi

echo -e "${GREEN}[OK]${NC} Ansible installed"
echo -e "${CYAN}[RUN]${NC} Starting automated setup...\n"

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Run the main playbook
ansible-playbook setup_complete.yml -K "$@"
