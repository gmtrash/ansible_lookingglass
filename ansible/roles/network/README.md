# Network Configuration Role for macvtap/Bridge Interfaces

This Ansible role configures secondary network interfaces (like `enp9s0`) that are connected via libvirt bridge (`br0`) to automatically obtain DHCP addresses.

## Problem

When VMs are configured with multiple network interfaces via libvirt bridges, the secondary interfaces may not automatically come up or request DHCP addresses, resulting in:

```
3: enp9s0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN
```

## Solution

This role configures the network interface using netplan (Ubuntu) or systemd-networkd to:
1. Automatically bring up the interface on boot
2. Request a DHCP address
3. Set appropriate route metrics to avoid conflicts with the primary interface

## VM Network Architecture

Based on the VM XML configurations in this repository:

```xml
<interface type='bridge'>
  <mac address='52:54:00:90:46:ff'/>
  <source bridge='br0'/>
  <model type='virtio'/>
  <address type='pci' domain='0x0000' bus='0x09' slot='0x00' function='0x0'/>
</interface>
```

- **Host side**: Bridge `br0` created with `nmcli` (see main README)
- **Guest side**: Interface `enp9s0` at PCI address 09:00.0
- **Expected behavior**: enp9s0 should auto-configure via DHCP

## Quick Fix

If you need to fix the interface immediately on the guest without running Ansible:

```bash
# On the guest VM (192.168.122.123):
sudo bash fix-macvtap-network.sh
```

This will:
1. Create a netplan configuration for enp9s0
2. Apply the configuration
3. Bring up the interface and request DHCP
4. Show the interface status

## Using the Ansible Role

```yaml
---
- name: Configure network interfaces
  hosts: gpu_hosts
  become: yes

  roles:
    - network
```

Or use the provided playbook:

```bash
ansible-playbook -i ansible/inventory ansible/network-setup.yml
```

## What Gets Configured

### Netplan Configuration (Ubuntu/Debian)

Creates `/etc/netplan/60-macvtap.yaml`:

```yaml
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
```

### Key Settings Explained

- `dhcp4: true` - Request IPv4 address via DHCP
- `optional: true` - Don't block boot if interface fails
- `route-metric: 200` - Lower priority than primary interface (default metric 100)

## Troubleshooting

### Interface still DOWN after configuration

Check if the bridge exists on the host:

```bash
# On the host:
sudo brctl show br0
# or
ip link show br0
```

If `br0` doesn't exist, create it (on the host):

```bash
# Using nmcli:
sudo nmcli connection add type bridge ifname br0
sudo nmcli connection add type ethernet ifname <physical-interface> master br0
```

### Interface UP but no DHCP

Check DHCP server logs on the host or router:

```bash
# On guest:
sudo dhclient -v enp9s0

# Check for DHCP traffic:
sudo tcpdump -i enp9s0 port 67 or port 68
```

### Verify VM Configuration

Ensure the VM XML has the bridge interface configured:

```bash
# On host:
sudo virsh dumpxml <vm-name> | grep -A 5 "interface type"
```

Should show `<source bridge='br0'/>` for the secondary interface.

### Manual Fallback

If netplan isn't working, configure manually:

```bash
# Bring up interface:
sudo ip link set enp9s0 up

# Request DHCP:
sudo dhclient enp9s0

# Check status:
ip addr show enp9s0
```

## Requirements

- Ubuntu 18.04+ or Debian 10+ (for netplan)
- libvirt bridge `br0` configured on host
- VM XML configured with bridge interface

## Files Created

- `/etc/netplan/60-macvtap.yaml` - Netplan configuration
- `/etc/systemd/network/10-enp9s0.network` - systemd-networkd fallback (if netplan unavailable)

## Host-Side Bridge Setup

For reference, the host-side bridge `br0` should be created using nmcli (as mentioned in main README):

```bash
# Create bridge
sudo nmcli connection add type bridge ifname br0 con-name br0

# Add physical interface to bridge (replace eno1 with your interface)
sudo nmcli connection add type bridge-slave ifname eno1 master br0

# Bring up bridge
sudo nmcli connection up br0
```

The bridge allows VMs to communicate with the physical network as if they were directly connected.
