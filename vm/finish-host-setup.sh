#!/bin/bash
# Final one-time host setup. Run with sudo:  sudo bash vm/finish-host-setup.sh
set -euo pipefail

# 1. Start libvirt on-demand sockets that exist on this distro
#    openSUSE/modular: all virt* sockets; Ubuntu/monolithic: virtlogd + virtlockd only
for u in virtstoraged.socket virtsecretd.socket virtnodedevd.socket virtlogd.socket virtlockd.socket; do
  if systemctl cat "$u" >/dev/null 2>&1; then
    systemctl enable --now "$u"
  else
    echo "skip $u (not present on this distro)"
  fi
done

# 2. Install libvirt qemu hook: DNAT host high ports -> guest 192.168.122.50
mkdir -p /etc/libvirt/hooks
cat > /etc/libvirt/hooks/qemu <<'HOOK'
#!/bin/bash
# Port forwards for casaos-vm (guest 192.168.122.50). Managed by RRRs project.
GUEST=192.168.122.50
TCP_PORTS="10022:22 18000:48000 19696:9696 17878:7878 18989:8989 18787:8787 18686:8686 18080:8080 18085:8085 16881:6881"
UDP_PORTS="16881:6881"

add_rules() {
  # Idempotent: wipe any previous instance of the table first, so re-running
  # (manual invocation, daemon restarts) never stacks duplicate rules.
  del_rules
  nft add table ip casaos_fw
  nft add chain ip casaos_fw prerouting '{ type nat hook prerouting priority dstnat; policy accept; }'
  nft add chain ip casaos_fw output     '{ type nat hook output     priority dstnat; policy accept; }'
  nft add chain ip casaos_fw forward    '{ type filter hook forward priority filter; policy accept; }'
  # MSS clamp: host WiFi uplink path MTU is 1280 (verified by DF ping bisect).
  # Guest PMTUD through NAT doesn't receive ICMP frag-needed, so TCP stalls
  # on large packets unless we clamp MSS on forwarded SYNs (both directions).
  nft add rule ip casaos_fw forward iifname "virbr0" tcp flags syn tcp option maxseg size set 1240
  nft add rule ip casaos_fw forward oifname "virbr0" tcp flags syn tcp option maxseg size set 1240
  for m in $TCP_PORTS; do
    hp=${m%%:*}; gp=${m##*:}
    nft add rule ip casaos_fw prerouting iifname != "virbr0" tcp dport $hp dnat to $GUEST:$gp
    nft add rule ip casaos_fw output     oifname "virbr0" tcp dport $hp dnat to $GUEST:$gp
    nft add rule ip casaos_fw forward    ip daddr $GUEST tcp dport $gp accept
  done
  for m in $UDP_PORTS; do
    hp=${m%%:*}; gp=${m##*:}
    nft add rule ip casaos_fw prerouting iifname != "virbr0" udp dport $hp dnat to $GUEST:$gp
    nft add rule ip casaos_fw output     oifname "virbr0" udp dport $hp dnat to $GUEST:$gp
    nft add rule ip casaos_fw forward    ip daddr $GUEST udp dport $gp accept
  done
  # Local-host access: packets to the host's OWN IP route via lo, so the
  # oifname rules above never match them. DNAT explicitly for the host IP
  # (auto-detected from the default-route interface, so it works on any NIC).
  HOST_IF=$(ip route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
  HOST_IP=$(ip -4 addr show "$HOST_IF" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
  if [ -n "$HOST_IP" ]; then
    for m in $TCP_PORTS; do
      hp=${m%%:*}; gp=${m##*:}
      nft add rule ip casaos_fw output ip daddr $HOST_IP tcp dport $hp dnat to $GUEST:$gp
    done
    for m in $UDP_PORTS; do
      hp=${m%%:*}; gp=${m##*:}
      nft add rule ip casaos_fw output ip daddr $HOST_IP udp dport $hp dnat to $GUEST:$gp
    done
  fi
}

del_rules() { nft delete table ip casaos_fw 2>/dev/null || true; }

[ "$1" = "casaos-vm" ] || exit 0
case "$2/$3" in
  start/begin)   add_rules ;;
  stopped/end|release/end) del_rules ;;
esac
exit 0
HOOK
chmod +x /etc/libvirt/hooks/qemu

# 3. Restart the libvirt daemon so it picks up the hook (running VMs survive).
if systemctl cat virtqemud.service >/dev/null 2>&1; then
  systemctl restart virtqemud
else
  systemctl restart libvirtd
fi

# 4. Hooks normally fire on VM start/stop events. If casaos-vm is already
#    running across this reinstall, apply the rules live right now instead of
#    waiting for the VM's next restart. add_rules is idempotent (wipe-then-add).
if virsh --connect qemu:///system domstate casaos-vm 2>/dev/null | grep -q running; then
  /etc/libvirt/hooks/qemu casaos-vm start begin
  echo "casaos-vm is running — port-forward + clamp rules applied live."
fi

echo "OK - sockets up, hook installed."
