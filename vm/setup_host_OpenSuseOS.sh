#!/bin/bash
# One-time host setup for the casaos-vm. Run with sudo:  sudo bash setup-host.sh
# NOTE: openSUSE Leap 16 uses MODULAR libvirt daemons (virtqemud), not libvirtd.
set -euo pipefail

# 1. Virtualization packages (virt-install/qemu already installed separately)
zypper --non-interactive install libvirt-daemon-qemu libvirt-daemon-driver-network libvirt-daemon-config-network

# 2. Modular daemons + default NAT network
systemctl enable --now virtqemud virtnetworkd
virsh net-start default 2>/dev/null || true
virsh net-autostart default

# 3. Let user 'je' run VMs without sudo (takes effect on next login)
usermod -aG libvirt,kvm je

echo "OK. Log out and back in (or 'newgrp libvirt'), then build the VM with build-vm.sh"
