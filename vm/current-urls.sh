#!/bin/bash
# Print all stack URLs for this machine. Machine-profile aware:
#   . vm/_machine.sh  → RRR_LAN_IP / RRR_URL_HOST / RRR_MDNS_OK
# mDNS (.local) names are ONLY offered when the selected machine profile says they
# resolve correctly there (ailab: docker bridges poison avahi → IP only).
. "$(dirname "$0")/_machine.sh"
IP="$RRR_LAN_IP"
if [ "$RRR_MDNS_OK" = "1" ]; then
  HN="$RRR_URL_HOST"
  echo "Host is $IP  (URL host $HN valid on this machine — set: $MACHINE_SET)"
else
  HN=""
  echo "Host is $IP  (mDNS NOT usable on this machine — use the IP. set: $MACHINE_SET)"
fi
for spec in "CasaOS 18000" "Prowlarr 19696" "Radarr 17878" "Sonarr 18989" "Readarr 18787" "Lidarr 18686" "qBittorrent 18085" "SABnzbd 18080" "ssh 10022"; do
  set -- $spec
  if [ "$1" = ssh ]; then
    printf '%-12s ssh -p %s debian@%s%s\n' "$1" "$2" "$IP" "${HN:+   (or $HN)}"
  else
    printf '%-12s http://%s:%s%s\n' "$1" "$IP" "$2" "${HN:+   (or http://$HN:$2)}"
  fi
done
