#!/bin/bash
# Build + launch casaos-vm (run as regular user AFTER setup-host.sh + re-login).
set -euo pipefail
cd "$(dirname "$0")"

DISKDIR="$HOME/VMs/casaos"
mkdir -p "$DISKDIR"

# System disk: fresh overlay on the verified base image, grown to 32G
qemu-img create -f qcow2 -F qcow2 -b "$PWD/debian-12-generic-amd64.qcow2" "$DISKDIR/system.qcow2" 32G

# Data disk: 200G for /DATA (media + downloads)
qemu-img create -f qcow2 "$DISKDIR/data.qcow2" 200G

# NoCloud seed ISO
rm -f seed.iso
mkisofs -output seed.iso -volid cidata -joliet -rock user-data meta-data network-config

sg libvirt -c "virt-install \
  --connect qemu:///system \
  --name casaos-vm \
  --memory 8192 --vcpus 4 \
  --cpu host-model \
  --disk path=$DISKDIR/system.qcow2,format=qcow2,bus=virtio \
  --disk path=$DISKDIR/data.qcow2,format=qcow2,bus=virtio \
  --disk path=$PWD/seed.iso,device=cdrom \
  --import --os-variant debian12 \
  --network network=default \
  --graphics none --noautoconsole \
  --autostart"

echo "VM launched. Provisioning (CasaOS install) runs automatically inside."
echo "Watch with: virsh console casaos-vm   or wait and run check-vm.sh"
