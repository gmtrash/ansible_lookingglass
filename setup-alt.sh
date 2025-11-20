#!/bin/bash
#############################################################################
##    Alternative Setup Script - For systems with sudo-rs                  ##
##    Pre-authenticates sudo before running Ansible                        ##
#############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Looking Glass VFIO Setup - Alternative (sudo-rs compatible)║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Pre-authenticate sudo
echo -e "${YELLOW}[INFO]${NC} Authenticating sudo (required for package installation)"
sudo -v

# Keep sudo alive in background
( while true; do sudo -v; sleep 50; done ) &
SUDO_LOOP_PID=$!
trap "kill $SUDO_LOOP_PID 2>/dev/null || true" EXIT

# Check for ansible
if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${YELLOW}[INFO]${NC} Ansible not found - installing...\n"

    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt install -y ansible
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y ansible
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm ansible
    else
        echo -e "${YELLOW}[ERROR]${NC} Could not install Ansible automatically"
        exit 1
    fi
    echo -e "${GREEN}[OK]${NC} Ansible installed\n"
else
    echo -e "${GREEN}[OK]${NC} Ansible found\n"
fi

echo -e "${CYAN}[INFO]${NC} Starting automated setup...\n"

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Run without -K since we've pre-authenticated sudo
# Individual tasks use become: true when they need sudo
ansible-playbook setup_complete.yml "$@"

# Kill the sudo keep-alive loop
kill $SUDO_LOOP_PID 2>/dev/null || true
