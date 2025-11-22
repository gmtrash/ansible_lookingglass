#!/bin/bash
#############################################################################
##              Quick Fix for NVRAM Permission Errors                     ##
##                 Wrapper for fix_nvram.yml playbook                     ##
#############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       Fix QEMU NVRAM Permission Denied Errors              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Get VM name from argument or use default
VM_NAME="${1:-win11}"

echo -e "${YELLOW}[INFO]${NC} Fixing NVRAM permissions for VM: ${GREEN}${VM_NAME}${NC}\n"

# Check for ansible
if ! command -v ansible-playbook &>/dev/null; then
    echo -e "${RED}[ERROR]${NC} Ansible not found. Please install it first:"
    echo "  Ubuntu/Debian: sudo apt install ansible"
    echo "  Fedora/RHEL:   sudo dnf install ansible"
    echo "  Arch:          sudo pacman -S ansible"
    exit 1
fi

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Run the fix playbook
VM_NAME="${VM_NAME}" ansible-playbook fix_nvram.yml "$@"

echo -e "\n${GREEN}[OK]${NC} Permission fix complete!"
echo -e "${CYAN}[INFO]${NC} Try starting your VM now: ${GREEN}virsh start ${VM_NAME}${NC}\n"
