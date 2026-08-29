#!/bin/bash
# Health check for casaos-vm provisioning progress.
set -uo pipefail
echo "=== VM state ==="
sg libvirt -c "virsh --connect qemu:///system domstate casaos-vm" 2>/dev/null || echo "VM not found"
echo "=== SSH into guest (via NAT IP until port-forward exists) ==="
timeout 8 ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 debian@192.168.122.50 "cloud-init status 2>/dev/null; echo ---; systemctl is-active casaos-gateway casaos docker 2>/dev/null; echo ---; ss -tln | grep -E ':(48000|9696|7878|8989|8787|8686) ' || echo 'arr ports not up yet'; echo ---; grep -c . /root/PROVISION_DONE.txt 2>/dev/null || echo 'provisioning still running'" 2>&1 | head -25
echo "=== CasaOS UI direct from guest ==="
timeout 5 curl -s -m 3 -o /dev/null -w "guest:48000 -> HTTP %{http_code}\n" http://192.168.122.50:48000/ 2>/dev/null || echo "no answer on guest :48000 yet"
