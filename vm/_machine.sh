#!/bin/bash
# _machine.sh — shared machine-profile resolver. NOT executable directly; source it:
#   . "$(dirname "$0")/_machine.sh"
# Value resolution order (per key): env override (RRR_*) > machines/current/machine.env
# > autodetect from the live system. Sourcing is cheap and failure-free: never exits,
# just falls back. M_* come from machine.env; RRR_* are the resolved values.
_rroot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MENV_PATH="$_rroot/machines/current/machine.env"
if [ -f "$MENV_PATH" ]; then . "$MENV_PATH"; else MACHINE_SET="${MACHINE_SET:-}"; fi

_def_if() { ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1; }
_def_ip() { ip -4 addr show "${1:-$RRR_LAN_IF}" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1; }
_nm_conn() { nmcli -t -f NAME,DEVICE,STATE con show 2>/dev/null | awk -F: -v d="$RRR_LAN_IF" '$2==d && $3=="activated"{print $1; exit}'; }

: "${RRR_LAN_IF:=${M_LAN_IF_DEFAULT:-$(_def_if)}}"
: "${RRR_LAN_IP:=${M_LAN_IP_DEFAULT:-$(_def_ip)}}"
: "${RRR_URL_HOST:=${M_URL_HOST:-$RRR_LAN_IP}}"
: "${RRR_NM_CONN:=${M_NM_CONN:-$(_nm_conn)}}"
: "${RRR_MDNS_OK:=${M_MDNS_OK:-0}}"
: "${RRR_HOST_PREP:=${M_HOST_PREP:-}}"
MACHINE_SET="${MACHINE_SET:-autodetect (run vm/select-machine.sh <set> to pin)}"
