#!/bin/bash
# Fix + apply port-forwards for the RUNNING casaos-vm. Run with sudo.
set -euo pipefail
NFT=/usr/sbin/nft

mkdir -p /etc/libvirt/hooks
cat > /etc/libvirt/hooks/qemu <<'HOOK'
#!/bin/bash
# Port forwards for casaos-vm (guest 192.168.122.50). Managed by RRRs project.
NFT=/usr/sbin/nft
GUEST=192.168.122.50
TCP_PORTS="10022:22 18000:48000 19696:9696 17878:7878 18989:8989 18787:8787 18686:8686 18080:8080 18085:8085 16881:6881"
UDP_PORTS="16881:6881"

add_rules() {
  del_rules
  $NFT add table ip casaos_fw
  $NFT add chain ip casaos_fw prerouting '{ type nat hook prerouting priority dstnat; policy accept; }'
  $NFT add chain ip casaos_fw output     '{ type nat hook output     priority dstnat; policy accept; }'
  $NFT add chain ip casaos_fw forward    '{ type filter hook forward priority filter; policy accept; }'
  for m in $TCP_PORTS; do
    hp=${m%%:*}; gp=${m##*:}
    $NFT add rule ip casaos_fw prerouting iifname != "virbr0" tcp dport $hp dnat to $GUEST:$gp
    $NFT add rule ip casaos_fw output     oifname "lo" tcp dport $hp dnat to $GUEST:$gp
    $NFT add rule ip casaos_fw forward    ip daddr $GUEST tcp dport $gp accept
  done
  for m in $UDP_PORTS; do
    hp=${m%%:*}; gp=${m##*:}
    $NFT add rule ip casaos_fw prerouting iifname != "virbr0" udp dport $hp dnat to $GUEST:$gp
    $NFT add rule ip casaos_fw output     oifname "lo" udp dport $hp dnat to $GUEST:$gp
    $NFT add rule ip casaos_fw forward    ip daddr $GUEST udp dport $gp accept
  done
}

del_rules() { $NFT delete table ip casaos_fw 2>/dev/null || true; }

[ "$1" = "casaos-vm" ] || exit 0
case "$2/$3" in
  start/begin)   add_rules ;;
  stopped/end|release/end) del_rules ;;
esac
exit 0
HOOK
chmod +x /etc/libvirt/hooks/qemu

# Apply now for the already-running VM (same call libvirt makes on start)
bash /etc/libvirt/hooks/qemu casaos-vm start begin

echo "=== casaos_fw table now: ==="
$NFT list table ip casaos_fw
