#!/bin/bash
# One-time host setup for the casaos-vm on Ubuntu/Debian. Run with sudo:  sudo bash vm/setup_host_Ubuntu.sh
# Encodes every Ubuntu-specific fix discovered 2026-09-19 (see REBUILD.md notes):
#   - libvirtd --timeout 120 + socket activation orphans dnsmasq and refuses to
#     re-adopt a running network on next activation -> make daemon persistent
#   - ghost dnsmasq processes / orphan virbr0 from partial setups block net-start
#   - a 'default' network defined in the user's SESSION daemon gives misleading
#     state readings; remove it so only the system daemon owns networking
#   - always use --connect qemu:///system explicitly (non-root virsh defaults
#     to the session daemon)
set -euo pipefail

# Detect active libvirt model (monolithic vs modular)
if systemctl list-unit-files virtqemud.service | grep -q 'enabled'; then
  LIBVIRT_MODEL="modular"
else
  LIBVIRT_MODEL="monolithic"
fi
echo "Detected libvirt model: $LIBVIRT_MODEL"

# 1. Virtualization packages (virtiofsd = daemon libvirt spawns for the
#    /DATA shared-folder passthrough)
apt-get install -y libvirt-daemon-system libvirt-clients libvirt-daemon-driver-network \
  qemu-kvm virtinst genisoimage sshpass nftables virtiofsd

# 2. Make the monolithic daemon persistent (no --timeout 120 self-exit).
#    When the socket-activated daemon exits while a network is running, the next
#    instance marks it inactive and net-start hits EADDRINUSE from orphaned
#    dnsmasq sockets. Blank override; safe + idempotent.
if [ "$LIBVIRT_MODEL" = "monolithic" ]; then
  mkdir -p /etc/systemd/system/libvirtd.service.d
  printf '[Service]\nEnvironment=LIBVIRTD_ARGS=\n' > /etc/systemd/system/libvirtd.service.d/override.conf
  systemctl daemon-reload
fi

# 3. Start daemons
if [ "$LIBVIRT_MODEL" = "modular" ]; then
  systemctl enable --now virtqemud virtnetworkd
else
  systemctl enable --now libvirtd
fi

# 4. Clean stale state from previous partial setups — only when the system
#    network is not already active (don't kill a healthy running network).
VIRSH="virsh --connect qemu:///system"
if ! $VIRSH net-info default 2>/dev/null | grep -q 'Active:.*yes'; then
  pkill -f '/var/lib/libvirt/dnsmasq/default.conf' 2>/dev/null || true
  ip link delete virbr0 2>/dev/null || true
fi

# 5. Remove the phantom 'default' network from the user's session daemon, if any
sudo -u je virsh --connect qemu:///session net-undefine default 2>/dev/null || true

# 6. Ensure the network is defined, then start + autostart it
$VIRSH net-info default >/dev/null 2>&1 || $VIRSH net-define /usr/share/libvirt/networks/default.xml
$VIRSH net-start default || true
$VIRSH net-autostart default

# 7. Let user 'je' run VMs without sudo (takes effect on next login)
usermod -aG libvirt,kvm je

echo "OK. Then run:"
echo "  1. sudo bash vm/finish-host-setup.sh   (port-forwards + MSS clamp hook)"
echo "  2. bash vm/build-vm.sh                 (from the repo root)"
