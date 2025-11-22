#!/bin/bash
#############################################################################
##           Looking Glass VFIO Setup - Bootstrap Script                   ##
##                      Minimal Ansible Launcher                           ##
##                                                                          ##
## Troubleshooting:                                                        ##
##   - NVRAM permission errors: Run ./fix_nvram.sh after setup             ##
##   - For help: See README.md or run with --help                          ##
#############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<EOF
${CYAN}╔════════════════════════════════════════════════════════════╗${NC}
${CYAN}║     Looking Glass VFIO Setup - Automated Installation     ║${NC}
${CYAN}╚════════════════════════════════════════════════════════════╝${NC}

${GREEN}Usage:${NC}
  ./setup.sh [ANSIBLE_OPTIONS]

${GREEN}Environment Variables:${NC}
  VM_NAME          VM name (default: win11)
  VM_MEMORY_GB     RAM in GB (default: 16)
  VM_VCPUS         CPU cores (default: 12)
  AUTO_REPLACE_VM  Replace existing VM without prompting (default: false)
  AUTO_START_VM    Start VM after creation (default: true)
  SKIP_ISO_DOWNLOAD Skip Windows ISO check (default: false)
  WINDOWS_ISO      Path to Windows 11 ISO

${GREEN}Examples:${NC}
  # Standard installation
  ./setup.sh

  # Custom VM specs
  VM_NAME=gaming VM_MEMORY_GB=32 VM_VCPUS=16 ./setup.sh

  # Skip auto-start
  AUTO_START_VM=false ./setup.sh

${GREEN}Troubleshooting Tools:${NC}
  ./fix_nvram.sh [VM_NAME]  - Fix NVRAM permission errors

${GREEN}Documentation:${NC}
  README.md - Full documentation
  ansible/fix_nvram.yml - NVRAM fix playbook

EOF
    exit 0
fi

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
echo -e "${CYAN}[INFO]${NC} You may be prompted for sudo password (only used when needed)\n"

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Run the main playbook
# -K asks for sudo password upfront (cached for tasks that need it)
# Individual tasks only use sudo when actually needed (packages, hugepages, etc.)
ansible-playbook setup_complete.yml -K "$@"
