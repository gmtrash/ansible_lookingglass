#!/bin/bash
#############################################################################
##           Fix Storage Permissions - libvirt-qemu Access                ##
##                                                                         ##
##  Fixes permission issues when libvirt-qemu cannot access disk files    ##
##  in user home directories (~/libvirt/images/)                          ##
#############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STORAGE_DIR="${1:-$HOME/libvirt}"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Fix Storage Permissions for libvirt-qemu            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

if [ ! -d "$STORAGE_DIR" ]; then
    echo -e "${YELLOW}[ERROR]${NC} Storage directory not found: $STORAGE_DIR"
    echo "Usage: $0 [storage_dir]"
    echo "Example: $0 ~/libvirt"
    exit 1
fi

echo -e "${CYAN}[INFO]${NC} Fixing permissions for: $STORAGE_DIR"
echo ""

# Check if user is in kvm group
if ! groups | grep -q kvm; then
    echo -e "${YELLOW}[WARN]${NC} You are not in the 'kvm' group!"
    echo "Add yourself with: sudo usermod -aG kvm $USER"
    echo "Then log out and back in."
    exit 1
fi

# Set group ownership to kvm
echo -e "${CYAN}[1/4]${NC} Setting group ownership to 'kvm'..."
chgrp -R kvm "$STORAGE_DIR"
echo -e "${GREEN}  ✓${NC} Group ownership set"

# Make parent directory executable for group (needed for traversal)
echo -e "\n${CYAN}[2/4]${NC} Setting parent directory execute permission..."
chmod g+x "$STORAGE_DIR"
echo -e "${GREEN}  ✓${NC} Parent directory accessible"

# Make images directory readable/writable/executable for group
echo -e "\n${CYAN}[3/4]${NC} Setting images directory permissions..."
if [ -d "$STORAGE_DIR/images" ]; then
    chmod g+rwx "$STORAGE_DIR/images"
    echo -e "${GREEN}  ✓${NC} Images directory permissions set"
else
    echo -e "${YELLOW}  ⚠${NC} Images directory not found (will be created when needed)"
fi

# Make disk files readable/writable for group
echo -e "\n${CYAN}[4/4]${NC} Setting disk file permissions..."
if ls "$STORAGE_DIR"/images/*.qcow2 &>/dev/null; then
    chmod g+rw "$STORAGE_DIR"/images/*.qcow2
    echo -e "${GREEN}  ✓${NC} Disk file permissions set"
else
    echo -e "${YELLOW}  ⚠${NC} No disk files found (will be created when needed)"
fi

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Permissions Fixed!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${CYAN}[INFO]${NC} Current permissions:"
ls -la "$STORAGE_DIR" | head -10
if [ -d "$STORAGE_DIR/images" ]; then
    echo ""
    ls -la "$STORAGE_DIR/images" | head -10
fi

echo -e "\n${GREEN}Next steps:${NC}"
echo "  Try starting your VM again: virsh start win11"
echo ""
echo -e "${YELLOW}Note:${NC} These permissions allow libvirt-qemu (system mode) to"
echo "  access your disk files via the 'kvm' group membership."
