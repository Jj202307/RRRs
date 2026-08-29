# RRRs — Practical Usage Guide

How to use the finished stack. (Build status: see NOTES-PROGRESS.md.
Optional next steps/upgrades: NEXT_STEPS_UPGRADES.md.)

## What you have

A VM (`casaos-vm`) on this machine running CasaOS with the *arr suite.
Everything is reached from your browser on this host (or LAN) via high ports.

## Daily URLs

**Use `P71.local` (this host's mDNS name — survives IP/DHCP changes), or the
current LAN IP (print it: `bash vm/current-urls.sh`).** Not `localhost`: the
port-forward DNATs to the VM, and the kernel blocks 127.0.0.1-sourced packets
from being forwarded (would need `route_localnet=1`, which weakens loopback
isolation — deliberately not enabled). Any IP the host owns works — the
forwarding rules match port+interface only.

| Service | URL (swap in `P71.local` freely) | What for |
|---|---|---|
| CasaOS | http://P71.local:18000 | App store, file manager, VM overview |
| Prowlarr | http://P71.local:19696 | Indexer manager + manual search/grab |
| Radarr | http://P71.local:17878 | Movies wishlist |
| Sonarr | http://P71.local:18989 | TV series |
| Readarr | http://P71.local:18787 | Books/comics |
| Lidarr | http://P71.local:18686 | Music |
| qBittorrent | http://P71.local:18085 | Torrent client (active) |
| SABnzbd | http://P71.local:18080 | Usenet client (idle until Phase B) |

## Typical workflows

### "I want movie X"
1. Open Radarr → Movies → Add New → search title → pick result → Add.
2. Radarr auto-searches (or click the magnifier on the movie) → pushes to
   qBittorrent (category "radarr") → downloads to `/DATA/Downloads/torrents`
   → on completion Radarr hardlinks/moves it to `/DATA/Media/Movies`.

### "I want TV show Y"
Sonarr → Series → Add New. Same pipeline (category "tv-sonarr"),
lands in `/DATA/Media/TV Shows`.

### "Grab this specific thing right now"
Prowlarr → Interactive Search across all indexers → download icon on the row.
Choose qBittorrent (torrent) — SABnzbd stays idle until you add a usenet
provider. This exact flow was tested end-to-end (310 MB Debian ISO, seeded).

### Books / music
Readarr (books) and Lidarr (music) work like Radarr, landing in
`/DATA/Media/Books` and `/DATA/Media/Music`. NOTE: no book/music indexers
configured yet — public ones fail validation; adding one needs an account on
a semi-private tracker (user decision).

### Finding downloaded files
- Finished media: CasaOS Files → `/DATA/Media/...` (or via CasaOS at :18000)
- Raw downloads: `/DATA/Downloads/torrents`, `/DATA/Downloads/usenet/{complete,incomplete}`

## Already configured (don't redo)

All app wiring is DONE (see NOTES-PROGRESS.md §8). What's in place:

- **Prowlarr**: indexers **YTS, Limetorrents, LinuxTracker, EZTV** (EZTV via
  FlareSolverr — installed as container `flaresolverr` guest :8191 and wired
  as a Prowlarr indexer proxy tagged `fs`; indexers must carry the same tag).
  1337x is Cloudflare-hard-blocked even via FlareSolverr — skip it.
  Download clients qBittorrent + SABnzbd (both tested OK). Apps
  Radarr/Sonarr/Readarr/Lidarr synced (fullSync).
- **Radarr/Sonarr/Readarr/Lidarr**: root folders /movies, /tv, /books,
  /music (container paths = /DATA/Media/*); download clients qBittorrent +
  SABnzbd with categories (radarr, tv-sonarr, readarr, lidarr); remote path
  mapping 172.17.0.1:/DATA/Downloads/ → /downloads/.
- **qBittorrent**: admin password set (vm/credentials.txt), default save
  path /DATA/Downloads/torrents (persists restarts).
- **SABnzbd**: wizard done, API key in vm/credentials.txt, categories
  created, dirs pointed at /DATA/Downloads/usenet/{complete,incomplete}.
  No usenet server yet (Phase B).
- Everything re-runnable/inspectable via `python3 vm/wire-arrs.py --stage
  verify` from the project dir.

## VM lifecycle (on the host)

```bash
# status / console
sg libvirt -c "virsh domstate casaos-vm"
sg libvirt -c "virsh console casaos-vm"        # Ctrl+] to exit

# stop / start (port-forward rules follow automatically via the qemu hook)
# NOT autostarted: VM stays off across host reboots until started by hand
sg libvirt -c "virsh -c qemu:///system shutdown casaos-vm"
sg libvirt -c "virsh -c qemu:///system start casaos-vm"

# into the VM over ssh (password in vm/credentials.txt, or the key ~/.ssh/id_ed25519)
ssh -p 10022 debian@192.168.1.81

# provisioning health check
bash vm/check-vm.sh
```

VM does NOT autostart with the host (user preference, disabled
2026-08-16) — start it manually: `sg libvirt -c "virsh -c qemu:///system
start casaos-vm"` (~40s to full stack). Port-forwards re-install
themselves on VM start. The whole stack is host-IP-agnostic (port-only
forwarding rules) — a DHCP address change breaks nothing; bookmarks should
use `P71.local`.

**VPN on the host**: fine. Full-tunnel VPNs carry the VM's traffic too
(desired); split-tunnel leaves it direct. Only a killswitch firewall that
drops all non-tunnel output would cut the VM's internet. Browser→VM access
is LAN-local and unaffected.

**If the VM is ever rebuilt from the seed**: re-apply the guest DNS fix
(netplan nameservers → 1.1.1.1/8.8.8.8, see NOTES §8e) — the seed still
carries the ISP-poisoned DNS order — then rerun `vm/wire-arrs.py` stages.

**Host DNS**: run once with sudo — `bash vm/fix-host-dns.sh` (sets
1.1.1.1/8.8.8.8 permanently via NetworkManager, kills the ISP's
torrent-domain DNS poisoning on the host too).

## Phase B later (usenet)

1. Buy a provider/block account. 2. SABnzbd (:18080) → Settings → Servers →
add host/port 563/user/pass → green handshake. 3. Prowlarr → add premium usenet
indexers if wanted. 4. In each arr ensure SABnzbd enabled as download client.
No reinstalls needed — that's why SABnzbd is already running.

## Disk growth

`/DATA` is a 200G virtual disk (`~/VMs/casaos/data.qcow2`), sparse — grows only
as used. To enlarge later: shut VM down, `qemu-img resize +100G` the disk,
`virsh start`, then `growpart` + `resize2fs` inside the guest (or via cloud-init).

## Full teardown (if ever)

See "Rollback / teardown" at the bottom of NOTES-PROGRESS.md.
