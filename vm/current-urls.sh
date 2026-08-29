#!/bin/bash
# Print all stack URLs for the CURRENT host IP + the IP-stable mDNS names.
IP=$(ip -4 addr show enp0s31f6 | grep -oP 'inet \K[0-9.]+(.?= )' | head -1)
IP=$(ip -4 addr show enp0s31f6 | grep -oP 'inet \K[0-9.]+' | head -1)
HN=$(hostname).local
echo "Host is $IP  (mDNS name $HN — survives IP changes)"
for spec in "CasaOS 18000" "Prowlarr 19696" "Radarr 17878" "Sonarr 18989" "Readarr 18787" "Lidarr 18686" "qBittorrent 18085" "SABnzbd 18080" "ssh 10022"; do
  set -- $spec
  if [ "$1" = ssh ]; then
    printf '%-12s ssh -p %s debian@%s   (or %s)\n' "$1" "$2" "$IP" "$HN"
  else
    printf '%-12s http://%s:%s   (or http://%s:%s)\n' "$1" "$IP" "$2" "$HN" "$2"
  fi
done
