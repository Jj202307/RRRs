#!/bin/bash
# Final one-time host setup. Run with sudo:  sudo bash vm/finish-host-setup.sh
set -euo pipefail

# 1. Start remaining modular libvirt sockets (on-demand daemons, no network exposure)
systemctl start virtstoraged.socket virtlogd.socket virtlockd.socket virtsecretd.socket virtnodedevd.socket
systemctl enable virtstoraged.socket virtlogd.socket virtlockd.socket virtsecretd.socket virtnodedevd.socket

# 2. Install libvirt qemu hook: DNAT host high ports -> guest 192.168.122.50
mkdir -p /etc/libvirt/hooks
cat > /etc/libvirt/hooks/qemu <<'HOOK'
#!/bin/bash
# Port forwards for casaos-vm (guest 192.168.122.50). Managed by RRRs project.
GUEST=192.168.122.50
TCP_PORTS="10022:22 18000:48000 19696:9696 17878:7878 18989:8989 18787:8787 18686:8686 18080:8080 18085:8085 16881:6881"
UDP_PORTS="16881:6881"

add_rules() {
  nft add table ip casaos_fw
  nft add chain ip casaos_fw prerouting '{ type nat hook prerouting priority dstnat; policy accept; }'
  nft add chain ip casaos_fw output     '{ type nat hook output     priority dstnat; policy accept; }'
  nft add chain ip casaos_fw forward    '{ type filter hook forward priority filter; policy accept; }'
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

# 3. Restart virtqemud so it picks up the hook (safe: no VMs running yet)
systemctl restart virtqemud

echo "OK - sockets up, hook installed."
