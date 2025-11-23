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

# Parse arguments
FORCE_NO_SUDO=false
for arg in "$@"; do
    if [[ "$arg" == "--no-sudo" ]]; then
        FORCE_NO_SUDO=true
    fi
done

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    cat <<EOF
${CYAN}╔════════════════════════════════════════════════════════════╗${NC}
${CYAN}║     Looking Glass VFIO Setup - Automated Installation     ║${NC}
${CYAN}╚════════════════════════════════════════════════════════════╝${NC}

${GREEN}Usage:${NC}
  ./setup.sh [OPTIONS] [ANSIBLE_OPTIONS]

${GREEN}Options:${NC}
  --help, -h       Show this help message
  --no-sudo        Skip sudo password prompt (packages must be installed)

${GREEN}Environment Variables:${NC}
  VM_NAME               VM name (default: win11)
  VM_MEMORY_GB          RAM in GB (default: 16)
  VM_VCPUS              CPU cores (default: 12)
  AUTO_REPLACE_VM       Replace existing VM without prompting (default: false)
  AUTO_START_VM         Start VM after creation (default: true)
  SKIP_ISO_DOWNLOAD     Skip Windows ISO check (default: false)
  SKIP_PACKAGE_INSTALL  Skip package installation (default: false)
  WINDOWS_ISO           Path to Windows 11 ISO

${GREEN}Examples:${NC}
  # Standard installation
  ./setup.sh

  # Custom VM specs
  VM_NAME=gaming VM_MEMORY_GB=32 VM_VCPUS=16 ./setup.sh

  # Skip auto-start
  AUTO_START_VM=false ./setup.sh

  # Skip sudo prompt (if packages already installed)
  ./setup.sh --no-sudo

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

echo -e "${CYAN}[INFO]${NC} Starting automated setup...\n"

# Check if we need sudo access (packages not installed)
NEED_SUDO=false
if ! command -v virsh &>/dev/null || ! command -v qemu-system-x86_64 &>/dev/null; then
    NEED_SUDO=true
    echo -e "${YELLOW}[INFO]${NC} Required packages not found - will need sudo access for installation"
fi

# Override if user specified --no-sudo
if [ "$FORCE_NO_SUDO" = true ]; then
    NEED_SUDO=false
    echo -e "${GREEN}[INFO]${NC} Running in --no-sudo mode"
fi

# Change to ansible directory
cd "$(dirname "$0")/ansible"

# Filter out --no-sudo from args to pass to ansible
ANSIBLE_ARGS=()
for arg in "$@"; do
    if [[ "$arg" != "--no-sudo" ]]; then
        ANSIBLE_ARGS+=("$arg")
    fi
done

# Run the main playbook
# Note: Not using -K flag to support sudo-rs (Rust sudo implementation)
# Ansible will prompt interactively when sudo is needed, which works with both
# standard sudo and sudo-rs
if [ "$NEED_SUDO" = true ]; then
    echo -e "${YELLOW}[INFO]${NC} Some tasks may prompt for sudo password interactively\n"
fi

ansible-playbook setup_complete.yml "${ANSIBLE_ARGS[@]}"
