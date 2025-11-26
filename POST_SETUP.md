# Post-Setup Manual Installation Steps

After running `./setup.sh`, you'll need to manually install a few system-level files that require root privileges. This follows the "prerequisite checker" philosophy where you maintain control over system changes.

## Required Manual Steps

### 1. Install Packages (if not already installed)

```bash
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients \
  virt-manager ovmf bridge-utils dnsmasq dmidecode pciutils
```

**Note:** The setup script only checks for packages - it doesn't install them automatically.

### 2. Install Libvirt Hooks (for automatic GPU switching)

```bash
sudo cp ~/.local/share/vfio-setup/qemu.hook /etc/libvirt/hooks/qemu
sudo chmod 755 /etc/libvirt/hooks/qemu
sudo systemctl restart libvirtd
```

**What this does:** Automatically binds/unbinds GPU from VFIO drivers when VM starts/stops

### 3. Install Libvirt NoSleep Service (optional but recommended)

```bash
sudo cp ~/.local/share/vfio-setup/libvirt-nosleep@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

**What this does:** Prevents host from sleeping while VM is running

### 4. Install Looking Glass Shared Memory Configuration

```bash
sudo cp ~/.local/share/vfio-setup/10-looking-glass.conf /etc/tmpfiles.d/
sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf
```

**What this does:** Sets proper permissions on `/dev/shm/looking-glass` so you can access Looking Glass without sudo

**Important:** After installing this, restart your VM for the new permissions to take effect.

### 5. Verify User Groups

```bash
groups $USER
```

Should show: `kvm` and `libvirt`

If not, add yourself:
```bash
sudo usermod -aG libvirt,kvm $USER
newgrp libvirt
```

## Quick All-in-One Script

If you want to run all the manual installation steps at once:

```bash
#!/bin/bash
# Run after ./setup.sh completes

# Install libvirt hooks
sudo cp ~/.local/share/vfio-setup/qemu.hook /etc/libvirt/hooks/qemu
sudo chmod 755 /etc/libvirt/hooks/qemu

# Install nosleep service
sudo cp ~/.local/share/vfio-setup/libvirt-nosleep@.service /etc/systemd/system/

# Install Looking Glass tmpfiles.d config
sudo cp ~/.local/share/vfio-setup/10-looking-glass.conf /etc/tmpfiles.d/
sudo systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf

# Reload systemd
sudo systemctl daemon-reload

# Restart libvirtd to load hooks
sudo systemctl restart libvirtd

echo "✓ Manual installation complete!"
echo "Restart your VM if it's running for Looking Glass permissions to take effect."
```

## Troubleshooting

### NVRAM Permission Errors

If you see "Permission denied" errors related to NVRAM files:

```bash
./fix_nvram.sh [VM_NAME]
```

Or manually:
```bash
VM_NAME=win11  # Change to your VM name
sudo mkdir -p /var/lib/libvirt/qemu/nvram
sudo cp ~/.local/share/libvirt/qemu/nvram/${VM_NAME}_VARS.fd /var/lib/libvirt/qemu/nvram/
sudo chown libvirt-qemu:kvm /var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd
sudo chmod 600 /var/lib/libvirt/qemu/nvram/${VM_NAME}_VARS.fd
```

### Looking Glass Permission Errors

If `looking-glass-client` shows "Permission denied" for `/dev/shm/looking-glass`:

1. Make sure you installed the tmpfiles.d config (step 4 above)
2. Restart your VM (permissions only apply to newly created files)
3. Verify: `ls -la /dev/shm/looking-glass` should show:
   ```
   -rw-rw---- 1 libvirt-qemu kvm 268435456 Nov 24 11:35 /dev/shm/looking-glass
   ```

### Hooks Not Running

If GPU isn't switching automatically:

1. Verify hook is installed: `ls -la /etc/libvirt/hooks/qemu`
2. Check logs: `sudo journalctl -u libvirtd -f` (while starting VM)
3. Ensure hook is executable: `sudo chmod 755 /etc/libvirt/hooks/qemu`

## Understanding the File Locations

**User Directories (no sudo required):**
- VM configs: `~/.local/share/vfio-setup/`
- VM disks/ISOs: `~/libvirt/images/` (or custom path)
- Template files: `~/.local/share/vfio-setup/*.{hook,service,conf}`

**System Directories (require sudo):**
- Libvirt hooks: `/etc/libvirt/hooks/qemu`
- Systemd services: `/etc/systemd/system/libvirt-nosleep@.service`
- Tmpfiles config: `/etc/tmpfiles.d/10-looking-glass.conf`
- NVRAM files: `/var/lib/libvirt/qemu/nvram/`

## Next Steps

After completing manual installation:

1. **Start your VM**: `virsh start win11`
2. **Connect via SPICE**: `remote-viewer spice://localhost:5900`
3. **Install VirtIO drivers in Windows** (for network)
4. **Install GPU drivers** (NVIDIA/AMD)
5. **Install Looking Glass HOST in Windows** (download from https://looking-glass.io/downloads)
6. **Run Looking Glass CLIENT on Linux**: `looking-glass-client -F`

See README.md for detailed instructions on each step.
