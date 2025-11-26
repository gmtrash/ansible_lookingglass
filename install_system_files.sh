#!/bin/bash
#############################################################################
##              Install System Files - Post-Setup Helper                   ##
##                                                                          ##
##  Run this after ./setup.sh to install system-level files that require   ##
##  sudo privileges (hooks, services, tmpfiles.d configs)                  ##
#############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TEMPLATE_DIR="$HOME/.local/share/vfio-setup"

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Install System Files - Post-Setup Helper             ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Check if template directory exists
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo -e "${RED}[ERROR]${NC} Template directory not found: $TEMPLATE_DIR"
    echo "Please run ./setup.sh first to generate template files."
    exit 1
fi

echo -e "${YELLOW}[INFO]${NC} This script will install the following system files:"
echo "  1. Libvirt hook: /etc/libvirt/hooks/qemu"
echo "  2. NoSleep service: /etc/systemd/system/libvirt-nosleep@.service"
echo "  3. Looking Glass config: /etc/tmpfiles.d/10-looking-glass.conf"
echo ""
echo -e "${YELLOW}[INFO]${NC} This requires sudo privileges."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Install libvirt hook
echo -e "\n${CYAN}[1/3]${NC} Installing libvirt hook..."
if [ -f "$TEMPLATE_DIR/qemu.hook" ]; then
    sudo mkdir -p /etc/libvirt/hooks
    sudo cp "$TEMPLATE_DIR/qemu.hook" /etc/libvirt/hooks/qemu
    sudo chmod 755 /etc/libvirt/hooks/qemu
    echo -e "${GREEN}  ✓${NC} Libvirt hook installed"
else
    echo -e "${YELLOW}  ⚠${NC} Template not found: $TEMPLATE_DIR/qemu.hook (skipping)"
fi

# Install nosleep service
echo -e "\n${CYAN}[2/3]${NC} Installing nosleep service..."
if [ -f "$TEMPLATE_DIR/libvirt-nosleep@.service" ]; then
    sudo cp "$TEMPLATE_DIR/libvirt-nosleep@.service" /etc/systemd/system/
    echo -e "${GREEN}  ✓${NC} NoSleep service installed"
else
    echo -e "${YELLOW}  ⚠${NC} Template not found: $TEMPLATE_DIR/libvirt-nosleep@.service (skipping)"
fi

# Install Looking Glass tmpfiles.d config
echo -e "\n${CYAN}[3/3]${NC} Installing Looking Glass shared memory config..."
if [ -f "$TEMPLATE_DIR/10-looking-glass.conf" ]; then
    sudo mkdir -p /etc/tmpfiles.d
    sudo cp "$TEMPLATE_DIR/10-looking-glass.conf" /etc/tmpfiles.d/
    sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf 2>/dev/null || true
    echo -e "${GREEN}  ✓${NC} Looking Glass config installed"
else
    echo -e "${YELLOW}  ⚠${NC} Template not found: $TEMPLATE_DIR/10-looking-glass.conf (skipping)"
fi

# Reload systemd and restart libvirtd
echo -e "\n${CYAN}[INFO]${NC} Reloading systemd and restarting libvirtd..."
sudo systemctl daemon-reload
sudo systemctl restart libvirtd

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              Installation Complete!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}Next steps:${NC}"
echo "  1. If your VM is running, restart it for Looking Glass permissions to take effect"
echo "  2. Start your VM: virsh start win11"
echo "  3. Connect via SPICE: remote-viewer spice://localhost:5900"
echo "  4. Install VirtIO network drivers in Windows"
echo "  5. Install GPU drivers in Windows"
echo "  6. Install Looking Glass HOST in Windows"
echo "  7. Run Looking Glass CLIENT: looking-glass-client -F"
echo ""
echo "See POST_SETUP.md for detailed instructions."
