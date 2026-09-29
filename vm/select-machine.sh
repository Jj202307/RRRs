#!/bin/bash
# select-machine.sh — activate a machine-profile set for THIS checkout.
#   bash vm/select-machine.sh P71|ailab|<custom>   activate a set
#   bash vm/select-machine.sh new <name>           create a set from TEMPLATE
#   bash vm/select-machine.sh status               show active set + resolved values
# What it does: points machines/current at the chosen set, syncs per-machine
# functional files (network-config) into vm/ (.backup kept of the previous),
# prints resolved values and the steps that still need sudo / a VM rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

SETS_DIR="machines"
list_sets() { find "$SETS_DIR" -maxdepth 1 -mindepth 1 -type d ! -name TEMPLATE -printf '%f\n' | sort; }

case "${1:-}" in
  status)
    cur="(none)"
    [ -L "$SETS_DIR/current" ] && cur="$(readlink "$SETS_DIR/current")"
    echo "active set: $cur   (available: $(list_sets | tr '\n' ' '))"
    # shellcheck source=/dev/null
    . vm/_machine.sh
    echo "  OS / host-prep : ${M_OS:-?} / ${RRR_HOST_PREP:-?}"
    echo "  LAN            : $RRR_LAN_IF  $RRR_LAN_IP"
    echo "  browser host   : $RRR_URL_HOST  (mDNS usable: $RRR_MDNS_OK)"
    echo "  NM connection  : ${RRR_NM_CONN:-(none detected)}"
    echo "  guest MTU      : ${M_GUEST_MTU:-(default 1500)}"
    exit 0 ;;
  new)
    [ -n "${2:-}" ] || { echo "usage: vm/select-machine.sh new <name>" >&2; exit 2; }
    [ -d "$SETS_DIR/$2" ] && { echo "set '$2' already exists" >&2; exit 1; }
    cp -r "$SETS_DIR/TEMPLATE" "$SETS_DIR/$2"
    echo "created $SETS_DIR/$2 from TEMPLATE — edit $SETS_DIR/$2/machine.env (+ NOTES.md), then: vm/select-machine.sh $2"
    exit 0 ;;
  "") usage=1 ;;
esac
[ "${usage:-0}" = 1 ] && { echo "usage: vm/select-machine.sh P71|ailab|<custom>|new <name>|status" >&2; exit 2; }

SET="$1"
[ -d "$SETS_DIR/$SET" ] || { echo "unknown set '$SET' — have: $(list_sets | tr '\n' ' ')" >&2; exit 1; }
[ -f "$SETS_DIR/$SET/machine.env" ] || { echo "$SETS_DIR/$SET/machine.env missing — incomplete set" >&2; exit 1; }

# Sync per-machine functional files into vm/ (previous copy kept as *.backup)
for f in network-config; do
  src="$SETS_DIR/$SET/$f"; dst="vm/$f"
  if [ -f "$src" ]; then
    if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
      cp "$dst" "$dst.backup"
      cp "$src" "$dst"
      echo "updated vm/$f (previous kept as vm/$f.backup)"
    else
      cp "$src" "$dst"
      echo "vm/$f already matches the set"
    fi
  fi
done

ln -sfn "$SET" "$SETS_DIR/current"
echo "active set: $SET"

# shellcheck source=/dev/null
. vm/_machine.sh
echo "  LAN: $RRR_LAN_IF  $RRR_LAN_IP   browser: $RRR_URL_HOST   mDNS: $RRR_MDNS_OK   guest MTU: ${M_GUEST_MTU:-(default)}"
echo
echo "Reminders:"
echo "  - seed.iso picks up the new network-config only on the NEXT bash vm/build-vm.sh (fresh VM)."
echo "  - running VMs are unaffected (their netplan is baked in); the hook auto-detects IP/NIC live."
echo "  - fresh-host steps needing sudo: $RRR_HOST_PREP + vm/finish-host-setup.sh (+ vm/fix-host-dns.sh if ISP poisons DNS)."
