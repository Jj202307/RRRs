#!/bin/bash
# Permanently set host DNS to 1.1.1.1 + 8.8.8.8 (bypasses ISP/router DNS).
# Host uses NetworkManager, connection "Wired connection 1" on enp0s31f6 (DHCP kept).
# Run with sudo. Reversible: see bottom.
set -euo pipefail
CON="Wired connection 1"

nmcli con mod "$CON" ipv4.dns "1.1.1.1 8.8.8.8" ipv4.ignore-auto-dns yes
nmcli con up "$CON"   # brief network blip while the connection re-applies

echo "=== new resolv.conf: ==="
grep nameserver /etc/resolv.conf || true
echo "=== verify (ISP used to poison torrent domains): ==="
getent hosts 1337x.to || echo "1337x still unresolvable (its CF block also affects DNS via some resolvers - 1.1.1.1 should answer)"
getent hosts eztvx.re >/dev/null && echo "eztvx.re resolves OK"

# REVERSE later with:
#   sudo nmcli con mod "$CON" ipv4.dns "" ipv4.ignore-auto-dns no && sudo nmcli con up "$CON"
