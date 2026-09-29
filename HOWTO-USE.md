# RRRs — Practical Usage Guide

How to use the finished stack. (Build status: see NOTES-PROGRESS.md.
Optional next steps/upgrades: NEXT_STEPS_UPGRADES.md. Machine profiles: MACHINES.md.)

## What you have

A VM (`casaos-vm`) on this machine running CasaOS with the *arr suite.
Everything is reached from your browser on this host (or LAN) via high ports.

## Daily URLs

**Print them fresh: `bash vm/current-urls.sh`** (machine-profile aware). The URL
host depends on the machine (sets A/B/C — see MACHINES.md):

- **ailab (set B, live):** use the LAN IP `192.168.1.66`. **NOT `ailab.local`** —
  this host runs Docker/Calico bridges that register with avahi, so `.local`
  resolves to `172.17.0.1` (docker0) junk and the URLs die.
- **P71 (set A):** `P71.local` worked there (no docker bridges).
- Any IP the host owns works — the forwarding rules match port+interface only.
  Not `localhost`: the DNAT forwards LAN-side packets and the kernel blocks
  127.0.0.1-sourced forwarding (`route_localnet=1` deliberately not enabled).

| Service     | URL (ailab — swap in any host IP) | What for                             |
| ----------- | -------------------------------- | ------------------------------------ |
| CasaOS      | http://192.168.1.66:18000        | App store, file manager, VM overview |
| Prowlarr    | http://192.168.1.66:19696        | Indexer manager + manual search/grab |
| Radarr      | http://192.168.1.66:17878        | Movies wishlist                      |
| Sonarr      | http://192.168.1.66:18989        | TV series                            |
| Readarr     | http://192.168.1.66:18787        | Books/comics                         |
| Lidarr      | http://192.168.1.66:18686        | Music                                |
| qBittorrent | http://192.168.1.66:18085        | Torrent client (active)              |
| SABnzbd     | http://192.168.1.66:18080        | Usenet client (idle until Phase B)   |

### Desktop icon — one click for everything

`bash vm/desktop-icon.sh` installs a **"RRRs Media VM"** icon on your desktop
(Ubuntu 24.04 + openSUSE Leap 15.6; re-run to refresh, `--remove` to uninstall).
Double-click it: starts the VM if it's off, waits for the web UIs, then opens
all 8 services above as Firefox tabs. The applications-menu entry adds
"Start VM only" / "Open web UIs only" actions. The LAN IP is resolved at click
time from the active machine set — no reinstall after `select-machine.sh`.

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

- **Prowlarr**: indexers **YTS, LinuxTracker, EZTV** (EZTV via
  FlareSolverr — installed as container `flaresolverr` guest :8191 and wired
  as a Prowlarr indexer proxy tagged `fs`; indexers must carry the same tag).
  1337x is Cloudflare-hard-blocked even via FlareSolverr — skip it.
  Limetorrents dropped 2026-09: `.fun` refused connections, `.com`→`.pro`
  redirect chain ends at a parked page — no live mirror found.
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

Start it (no sudo, from the project dir):
```
bash vm/vm-power.sh start
```

```bash
# status / console
sg libvirt -c "virsh domstate casaos-vm"
sg libvirt -c "virsh console casaos-vm"        # Ctrl+] to exit

# stop / start (port-forward rules follow automatically via the qemu hook)
# VM is autostarted with the host (build-vm.sh --autostart + persistent libvirtd)
sg libvirt -c "virsh -c qemu:///system shutdown casaos-vm"
sg libvirt -c "virsh -c qemu:///system start casaos-vm"

# into the VM over ssh (password in vm/credentials.txt, or the key ~/.ssh/id_ed25519)
ssh -p 10022 debian@192.168.1.66
# provisioning health check
bash vm/check-vm.sh
```

VM autostarts with the host (build-vm.sh `--autostart`; the original host
had it disabled as a preference — `virsh autostart --disable casaos-vm`
restores that). ~40s to full stack. Port-forwards re-install themselves on
VM start. The whole stack is host-IP-agnostic (port-only
forwarding rules) — a DHCP address change breaks nothing; bookmarks should
use `P71.local`.

**VPN on the host (Surfshark) — verified 2026-09-29, zero config**: toggle the
Surfshark app and the VM follows automatically. Its policy routing catches the
VM's NATed traffic too (measured: VM egress == host egress == Surfshark exit
node, all services stay reachable, kill switch doesn't break the forwards).
Guest DNS follows the host chain: Surfshark's pushed resolvers while connected,
1.1.1.1 when not — no leak path either way (both ride the tunnel when it's up).
Details: `machines/ailab/NOTES.md`.

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

`/DATA` (guest) is a **virtiofs share of `/home/je/NVMe4TB/RRRs_VM/RRRs_DATA/`**
on the host — plain files, no virtual disk. Capacity = free space on the
NVMe volume; "resizing" is a filesystem-level concern of the host, nothing
to do inside the VM. Back it up like any directory (rsync, borg, snapshots);
for crash-consistent *arr databases, stop the VM or the apps first.

## Full teardown (if ever)

See "Rollback / teardown" at the bottom of NOTES-PROGRESS.md.
