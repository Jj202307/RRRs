#!/bin/bash
# vm-power.sh — start / stop / restart / status the casaos-vm. Run on the host, no sudo.
#   ./vm/vm-power.sh status | start | stop | force-stop | restart
# Port-forward nft rules are re-applied automatically by /etc/libvirt/hooks/qemu
# every time the VM starts — nothing extra to run.
# 'sg libvirt' is used because shells opened before je joined the libvirt group
# still lack the group; sg works in both cases.
set -euo pipefail
VM=casaos-vm

v() { sg libvirt -c "virsh --connect qemu:///system $*"; }

state() { v domstate "$VM" 2>/dev/null | head -1; }

wait_state() { # $1 = wanted state, $2 = max seconds
  local want=$1 max=${2:-90} waited=0
  while [ "$waited" -lt "$max" ]; do
    [ "$(state)" = "$want" ] && return 0
    sleep 2; waited=$((waited + 2))
  done
  return 1
}

case "${1:-status}" in
  status)
    echo "state:    $(state)"
    echo "autostart: $(v dominfo "$VM" | awk '/Autostart/ {print $2}')"
    ;;
  start)
    if [ "$(state)" = "running" ]; then echo "already running"; exit 0; fi
    v start "$VM"
    echo "starting..."; wait_state running 30 && echo "running" || echo "check: ./vm/vm-power.sh status"
    ;;
  stop)
    if [ "$(state)" != "running" ]; then echo "not running ($(state))"; exit 0; fi
    v shutdown "$VM"   # clean ACPI shutdown — CasaOS stops docker, then powers off
    echo "shutting down (clean)..."
    if wait_state "shut off" 90; then echo "stopped"; else
      echo "still shutting down after 90s — check again, or force: ./vm/vm-power.sh force-stop"
      exit 1
    fi
    ;;
  force-stop)
    echo "WARNING: unclean power-off (like pulling the plug)."
    v destroy "$VM"
    echo "stopped (unclean)"
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  *)
    echo "usage: $0 {status|start|stop|force-stop|restart}" >&2
    exit 2
    ;;
esac
