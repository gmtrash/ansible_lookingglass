sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients virt-manager ovmf bridge-utils dnsmasq dmidecode pciutils


sudo cp /home/aubreybailey/.local/share/vfio-setup/qemu.hook /etc/libvirt/hooks/qemu
sudo chmod 755 /etc/libvirt/hooks/qemu
sudo systemctl restart libvirtd

sudo cp /home/aubreybailey/.local/share/vfio-setup/libvirt-nosleep@.service /etc/systemd/system/
sudo systemctl daemon-reload

sudo chown aubreybailey:aubreybailey /home/aubreybailey/.local/share/libvirt/qemu/nvram/win11_VARS.fd

sudo mkdir -p /var/lib/libvirt/qemu/nvram && \
  sudo cp /home/aubreybailey/.local/share/libvirt/qemu/nvram/win11_VARS.fd /var/lib/libvirt/qemu/nvram/ && \
  sudo chown libvirt-qemu:kvm /var/lib/libvirt/qemu/nvram/win11_VARS.fd && \
  sudo chmod 600 /var/lib/libvirt/qemu/nvram/win11_VARS.fd


# after install?
  sudo cp /home/aubreybailey/.local/share/vfio-setup/qemu.hook /etc/libvirt/hooks/qemu
  sudo chmod 755 /etc/libvirt/hooks/qemu
  sudo systemctl restart libvirtd