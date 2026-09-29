#!/bin/bash
# After a fresh rebuild: every app generated NEW API keys on first boot, so
# the keys committed in this repo (original instance) don't work.
# This extracts the current keys from the running VM and prints a
# paste-ready block for vm/wire-arrs.py + vm/credentials.txt.
# Requires: sshpass on the host, VM up + provisioned, apps running,
# SABnzbd first-boot wizard completed (see REBUILD.md).
set -euo pipefail
cd "$(dirname "$0")/.."
. vm/_machine.sh
HOST="${RRR_HOST:-$RRR_LAN_IP}"
CREDS=vm/credentials.txt

# Prefer SSH key auth (ailab flow: je@aillab key is in user-data);
# fall back to sshpass + VM password (openSUSE/P71 flow) when no key works.
SSHOPTS=(-p 10022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8)
if ssh "${SSHOPTS[@]}" -o BatchMode=yes "debian@$HOST" true 2>/dev/null; then
  run() { ssh "${SSHOPTS[@]}" "debian@$HOST" "$1" 2>/dev/null; }
else
  PW=$(sed -n 's/^SSH password: //p' "$CREDS" | head -1)
  [ -n "$PW" ] || { echo "ERROR: no 'SSH password:' line in $CREDS and key auth failed" >&2; exit 1; }
  command -v sshpass >/dev/null || {
    echo "ERROR: key auth failed and sshpass not installed (Debian/Ubuntu: apt install sshpass)" >&2
    exit 1
  }
  run() { sshpass -p "$PW" ssh "${SSHOPTS[@]}" "debian@$HOST" "$1" 2>/dev/null; }
fi
jsonkey() { run "sudo docker exec $1 grep -o '\"ApiKey\": *\"[a-f0-9]*\"' /config/$2 | head -1 | cut -d'\"' -f4"; }
xmlkey()  { run "sudo docker exec $1 grep -o '<ApiKey>[^<]*</ApiKey>' /config/config.xml | head -1 | sed 's/<[^>]*>//g'"; }

# All five *arr apps (hotio images) keep their key in /config/config.xml
P=$(xmlkey prowlarr)
R=$(xmlkey radarr)
S=$(xmlkey sonarr)
D=$(xmlkey readarr)
L=$(xmlkey lidarr)
SAB_RAW=$(run "sudo docker exec sabnzbd grep -E '^(api_key|nzb_key|nzb_keys)' /config/sabnzbd.ini")
SAB_API=$(printf '%s\n' "$SAB_RAW" | sed -n 's/^api_key[ =]*//p' | head -1)
SAB_NZB=$(printf '%s\n' "$SAB_RAW" | sed -n 's/^nzb_keys\?[ =]*//p' | head -1)

for v in P R S D L; do
  [ -n "${!v}" ] || { echo "ERROR: failed to collect key for $v — VM up? app running? config filename changed?" >&2; exit 1; }
done
[ -n "$SAB_API" ] || { echo "ERROR: no api_key in sabnzbd.ini — complete the SABnzbd first-boot wizard first" >&2; exit 1; }

cat <<EOF
Fresh-build keys — apply these edits:

vm/wire-arrs.py — replace the APPS dict values and SAB_APIKEY:
    "prowlarr": (f"http://{HOST}:19696", "$P", "v1"),
    "radarr":   (f"http://{HOST}:17878", "$R", "v3"),
    "sonarr":   (f"http://{HOST}:18989", "$S", "v3"),
    "readarr":  (f"http://{HOST}:18787", "$D", "v1"),
    "lidarr":   (f"http://{HOST}:18686", "$L", "v1"),
  SAB_APIKEY = "$SAB_API"

vm/credentials.txt — refresh the API keys section:
  Prowlarr    = $P
  Radarr      = $R
  Sonarr      = $S
  Readarr     = $D
  Lidarr      = $L
  SABnzbd     = $SAB_API
  SABnzbd nzb_key = ${SAB_NZB:-<not found — inspect /config/sabnzbd.ini in the VM>}
EOF
