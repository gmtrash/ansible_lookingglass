#!/bin/bash
# Quick fix script for macvtap interface (enp9s0) not coming up
# Run this on the guest VM: sudo bash fix-macvtap-network.sh

set -e

echo "=== Fixing macvtap interface enp9s0 ==="

# Backup existing netplan configs
if [ -d /etc/netplan ]; then
    echo "Backing up existing netplan configuration..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    for config in /etc/netplan/*.yaml; do
        if [ -f "$config" ]; then
            cp "$config" "${config}.backup-${timestamp}"
            echo "  Backed up: $config"
        fi
    done
fi

# Create netplan configuration for enp9s0
echo "Creating netplan configuration for enp9s0..."
cat > /etc/netplan/60-macvtap.yaml <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp9s0:
      dhcp4: true
      dhcp6: false
      optional: true
      dhcp4-overrides:
        route-metric: 200
EOF

chmod 600 /etc/netplan/60-macvtap.yaml
echo "  Created: /etc/netplan/60-macvtap.yaml"

# Apply netplan configuration
echo "Applying netplan configuration..."
netplan apply

# Wait a moment for the interface to initialize
sleep 3

# Check interface status
echo ""
echo "=== Interface Status ==="
ip addr show enp9s0

# Check if we got an IP
if ip addr show enp9s0 | grep -q "inet "; then
    echo ""
    echo "✓ SUCCESS: enp9s0 is UP and has an IP address"
    ip -4 addr show enp9s0 | grep inet
else
    echo ""
    echo "⚠ WARNING: enp9s0 is UP but did not get an IP address"
    echo "  Possible issues:"
    echo "  1. DHCP server not reachable on this network"
    echo "  2. macvtap bridge on host not configured correctly"
    echo "  3. Check host-side macvtap configuration"
    echo ""
    echo "  Trying manual DHCP request..."
    dhclient -v enp9s0 2>&1 | tail -20
fi

echo ""
echo "=== All Network Interfaces ==="
ip addr show

echo ""
echo "Done! Configuration is persistent across reboots."
