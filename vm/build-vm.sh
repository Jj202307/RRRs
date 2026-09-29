#!/bin/bash
# Build + launch casaos-vm (run as regular user AFTER setup-host + re-login).
# Machine-profile aware: run vm/select-machine.sh <set> first; the seed picks up
# that set's network-config (guest MTU / DNS order). DISKDIR via RRR_DISKDIR.
set -euo pipefail
cd "$(dirname "$0")"
. ./_machine.sh
echo "machine set: $MACHINE_SET   LAN: $RRR_LAN_IF $RRR_LAN_IP   guest MTU: ${M_GUEST_MTU:-(default 1500)}"

DISKDIR="${RRR_DISKDIR:-/home/je/NVMe4TB/RRRs_VM}"
mkdir -p "$DISKDIR"

# Data lives OUTSIDE the VM via virtiofs: guest /DATA == host RRRs_DATA dir.
# Plain files on the host, browsable/backupable without the VM, shared with
# host apps while the VM runs. (Replaces the old 200G data.qcow2 design.)
DATADIR="$DISKDIR/RRRs_DATA"
mkdir -p "$DATADIR"

# System disk: fresh overlay on the verified base image, grown to 32G
qemu-img create -f qcow2 -F qcow2 -b "$PWD/debian-12-generic-amd64.qcow2" "$DISKDIR/system.qcow2" 32G

# NoCloud seed ISO
rm -f seed.iso
mkisofs -output seed.iso -volid cidata -joliet -rock user-data meta-data network-config

sg libvirt -c "virt-install \
  --connect qemu:///system \
  --name casaos-vm \
  --memory 8192 --vcpus 4 \
  --cpu host-model \
  --disk path=$DISKDIR/system.qcow2,format=qcow2,bus=virtio \
  --disk path=$PWD/seed.iso,device=cdrom \
  --filesystem type=mount,driver.type=virtiofs,source.dir=$DATADIR,target.dir=rrrs-data \
  --memorybacking source.type=memfd,access.mode=shared \
  --import --os-variant debian12 \
  --network network=default \
  --graphics none --noautoconsole \
  --autostart"

echo "VM launched. Provisioning (CasaOS install) runs automatically inside."
echo "Watch with: virsh console casaos-vm   or wait and run check-vm.sh"
