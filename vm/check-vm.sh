#!/bin/bash
# Health check for casaos-vm provisioning progress.
# SSH: uses ~/.ssh/id_ed25519 if present, else the password from
# credentials.txt via sshpass (fresh machines don't have the original key).
set -uo pipefail
cd "$(dirname "$0")"
if [ -f ~/.ssh/id_ed25519 ]; then
  SSH_CMD=(ssh -i ~/.ssh/id_ed25519)
else
  PW=$(sed -n 's/^SSH password: //p' credentials.txt | head -1)
  if command -v sshpass >/dev/null && [ -n "$PW" ]; then
    SSH_CMD=(sshpass -p "$PW" ssh)
  else
    echo "no ~/.ssh/id_ed25519 and no sshpass — skipping guest ssh check"
    SSH_CMD=()
  fi
fi
echo "=== VM state ==="
sg libvirt -c "virsh --connect qemu:///system domstate casaos-vm" 2>/dev/null || echo "VM not found"
echo "=== SSH into guest (via NAT IP until port-forward exists) ==="
if [ ${#SSH_CMD[@]} -gt 0 ]; then
  timeout 8 "${SSH_CMD[@]}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 debian@192.168.122.50 "cloud-init status 2>/dev/null; echo ---; systemctl is-active casaos-gateway casaos docker 2>/dev/null; echo ---; ss -tln | grep -E ':(48000|9696|7878|8989|8787|8686) ' || echo 'arr ports not up yet'; echo ---; grep -c . /root/PROVISION_DONE.txt 2>/dev/null || echo 'provisioning still running'" 2>&1 | head -25
fi
echo "=== CasaOS UI direct from guest ==="
timeout 5 curl -s -m 3 -o /dev/null -w "guest:48000 -> HTTP %{http_code}\n" http://192.168.122.50:48000/ 2>/dev/null || echo "no answer on guest :48000 yet"
