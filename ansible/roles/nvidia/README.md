# Ansible Role: NVIDIA Driver Installation

This Ansible role installs and configures NVIDIA drivers on Ubuntu/Debian systems. It handles common installation issues including broken apt dependencies and improper package removal.

## Key Features

- **Fixed apt dependency issues**: Automatically fixes broken apt dependencies before package operations
- **Proper shell piping**: Uses correct Ansible modules for command piping (not literal pipe characters)
- **Idempotent**: Can be run multiple times safely
- **Nouveau blacklisting**: Automatically blacklists the nouveau driver
- **Optional CUDA support**: Can install CUDA toolkit if needed
- **Verification**: Checks installation with dpkg and nvidia-smi

## Fixed Issues

This role specifically addresses:

1. **Line 140 Error**: Fixed improper use of pipe character in verification task
   - Changed from: `command: dpkg -l '|' grep -i nvidia-driver`
   - To: `shell: dpkg -l | grep -i nvidia-driver`

2. **Line 14 Error**: Fixed broken apt dependencies before package removal
   - Added: `apt-get --fix-broken install` task before package removal
   - Improved error handling with `ignore_errors` and proper state checking

## Requirements

- Ansible 2.9 or higher
- Target system: Ubuntu or Debian
- Root/sudo access on target system

## Role Variables

Available variables are listed below, along with default values (see `defaults/main.yml`):

```yaml
# Set to true to install CUDA toolkit
install_cuda: false

# NVIDIA driver version (default: 580)
nvidia_driver_version: "580"

# Whether to add graphics-drivers PPA (Ubuntu only)
add_nvidia_ppa: true

# Whether to purge existing NVIDIA packages before installation
purge_existing: true
```

## Dependencies

None.

## Example Playbook

```yaml
---
- name: Install NVIDIA drivers
  hosts: gpu_hosts
  become: yes

  roles:
    - nvidia

  vars:
    install_cuda: true  # Optional: install CUDA toolkit
```

## Quick Start

1. Copy the inventory example:
   ```bash
   cp ansible/inventory.example ansible/inventory
   ```

2. Edit the inventory file with your target host(s):
   ```ini
   [gpu_hosts]
   192.168.122.123 ansible_user=ubuntu
   ```

3. Run the playbook:
   ```bash
   ansible-playbook -i ansible/inventory ansible/nvidia-install.yml
   ```

4. Reboot the system after installation:
   ```bash
   ansible gpu_hosts -i ansible/inventory -b -m reboot
   ```

5. Verify installation:
   ```bash
   ansible gpu_hosts -i ansible/inventory -b -a "nvidia-smi"
   ```

## What This Role Does

1. **Preparation Phase**:
   - Updates apt cache
   - Fixes any broken apt dependencies
   - Removes existing NVIDIA packages cleanly

2. **Installation Phase**:
   - Adds NVIDIA PPA (Ubuntu only)
   - Installs NVIDIA driver and utilities
   - Optionally installs CUDA toolkit

3. **Configuration Phase**:
   - Blacklists nouveau driver
   - Sets up CUDA environment variables (if CUDA installed)
   - Updates initramfs

4. **Verification Phase**:
   - Checks installed NVIDIA packages
   - Runs nvidia-smi to verify driver functionality
   - Alerts if system reboot is required

## Troubleshooting

### Broken apt dependencies
If you encounter "Unmet dependencies" errors, this role automatically runs:
```bash
apt-get --fix-broken install -y
```

### Driver not loading after installation
A system reboot is required after NVIDIA driver installation. The role will notify you when a reboot is needed.

### Multiple NVIDIA driver versions installed
The role removes existing NVIDIA packages before installation. If you encounter conflicts, manually run:
```bash
sudo apt-get autoremove --purge 'nvidia-*'
sudo apt-get autoclean
```

### Nouveau still loading
Check if blacklist is in place:
```bash
cat /etc/modprobe.d/blacklist-nouveau.conf
```

Rebuild initramfs:
```bash
sudo update-initramfs -u
sudo reboot
```

## License

MIT

## Author Information

This role was created to address common NVIDIA driver installation issues, specifically:
- Broken apt dependency chains
- Improper shell command piping in Ansible tasks
- Incomplete nouveau driver blacklisting
