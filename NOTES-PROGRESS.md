# RRRs Implementation Log — Steps Taken & Succeeded

Living document. Chronological record of what was done, verified, and what's pending.
Host: openSUSE Leap 16.0, 8 cores / 62 GB RAM, 629 GB free on `/`. User `je` (uid 1000).

## Final architecture (decided)

```
openSUSE host (untouched except libvirt + 1 nft table)
  └── KVM VM "casaos-vm" (4 vCPU / 8 GB RAM, Debian 12)
        ├── CasaOS (web UI on guest :48000 -> host :18000)
        ├── Docker inside VM runs:
        │     Prowlarr  guest :9696 -> host :19696
        │     Radarr   guest :7878 -> host :17878
        │     Sonarr   guest :8989 -> host :18989
        │     Readarr  guest :8787 -> host :18787
        │     Lidarr   guest :8686 -> host :18686
        │     SABnzbd  guest :8080 -> host :18080   (idle until usenet provider)
        │     qBittorrent guest :8085 -> host :18085 (torrents; +16881 tcp/udp)
        └── /DATA inside guest = separate 200G qcow2 disk (ext4, label=data)
              /DATA/Media/{movies,tv,books,music}
              /DATA/Downloads/{usenet/{complete,incomplete},torrents}
```

Nothing on the host listens on port 80. All host-facing ports are high and were
verified free before use: 10022, 18000, 19696, 17878, 18989, 18787, 18686,
18080, 18085, 16881.

## Step log

### 1. Research — CasaOS on openSUSE? (DONE)
- Fetched and audited the official installer (`get.casaos.io`, v0.4.16) and the
  v0.4.15 release scripts. Result: openSUSE is NOT supported — the per-OS setup
  dispatcher (`03-setup-casaos.sh`) only knows arch/debian/ubuntu and exits 1 on
  everything else, but only AFTER copying files to `/`, restarting Docker,
  creating a `devmon` user (uid 300), rewriting `/etc/udevil/udevil.conf`,
  editing `/etc/conf.d/devmon`, and creating a Docker systemd override.
  Bare-metal install on this host: rejected.
- No official CasaOS docker image exists (it manages Docker; needs systemd + host fs).
- Decision: **KVM VM running Debian 12 + official CasaOS installer inside**.
  All CasaOS/host-fs weirdness is contained in a disposable qcow2.

### 2. Research — VM automation (DONE)
- Debian 12 `generic` cloud image (not `genericcloud`) is the recommended
  variant for libvirt `--import` + NoCloud seed. Verified URL + SHA512SUMS.
- CasaOS has no scriptable ISO (releases contain tarballs only) → cloud image
  + cloud-init `runcmd: curl get.casaos.io | bash` is the supported path.
- libvirt has no native host->guest port forward for NAT networks → solved
  with a qemu hook + own nft table (`casaos_fw`), firewalld untouched.

### 3. Host prep — what was installed (DONE, with user-run sudo)
User ran (verified successful):
- `zypper install qemu virt-install` (+ libvirt-client/libs pulled in)
- `zypper install libvirt-daemon-qemu libvirt-daemon-driver-network libvirt-daemon-config-network`
- `systemctl enable --now virtqemud virtnetworkd`  (Leap 16 = MODULAR daemons;
  `libvirtd.service` does not exist on Leap 16 — that was an error we hit and fixed)
- `virsh net-start default && virsh net-autostart default`
- `usermod -aG libvirt,kvm je`
Verified after: daemons active, `default` NAT net active+autostart, `je` in both groups,
`sg libvirt -c "virsh ..."` works without sudo.
Firewall/LAN diff vs pre-install baseline: unchanged (only virbr0-internal
192.168.122.1:53/67 bindings added; public zone identical).

### 4. Files staged in `vm/` (DONE)
- `debian-12-generic-amd64.qcow2` — downloaded, `sha512sum -c` OK
- `user-data` / `meta-data` / `network-config` — NoCloud seed:
  - guest static IP 192.168.122.50/24, gw/dns 192.168.122.1 (+1.1.1.1)
  - user `debian`, password auth + ed25519 key (`~/.ssh/id_ed25519`, created here)
  - formats `/dev/vdb` (the 200G data disk) as ext4, mounts at `/DATA`
  - runcmd: official CasaOS installer, then forces gateway port to **48000**
    (`/etc/casaos/gateway.ini` `[gateway] port`), restarts gateway, creates the
    `/DATA/Media|Downloads` tree, writes `/root/PROVISION_DONE.txt`
- `seed.iso` — built with mkisofs (volid cidata)
- `~/VMs/casaos/system.qcow2` — 32G overlay on the base image
- `~/VMs/casaos/data.qcow2` — 200G blank data disk
- `setup-host.sh`, `finish-host-setup.sh`, `build-vm.sh`, `check-vm.sh`
- `credentials.txt` — VM ssh password, port map

### 5. First VM launch attempt (FAILED — expected modular-libvirt gap)
`virt-install` failed: `virtstoraged-sock` missing. Cause: on modular libvirt,
`virtqemud` alone isn't enough; the companion daemon sockets
(storage/log/lock/secret/nodedev) were enabled but not started.
Fix staged in `finish-host-setup.sh` (also fixes `--cpu host` deprecation →
`host-model` in build-vm.sh).

### 6. Final host setup (DONE — user ran `finish-host-setup.sh`)
Companion sockets started+enabled; qemu hook installed; virtqemud restarted.

### 7. VM build + provisioning (DONE)
`build-vm.sh` created `~/VMs/casaos/{system,data}.qcow2` + seed, virt-install
succeeded, VM autostarts (later DISABLED on user request 2026-08-16: VM shut
down + `virsh autostart --disable` — stays off across host reboots; start
manually per HOWTO-USE.md §lifecycle). Guest came up at 192.168.122.50;
cloud-init ran the
CasaOS installer (completed), forced gateway port 48000, built /DATA tree.
Post-install the VM rebooted itself once (normal first-boot behavior).
Caveats hit & resolved:
- cloud-init `status --wait` as last runcmd self-deadlocks → `cloud-init status`
  shows "running" forever and `/root/PROVISION_DONE.txt` (last-but-one step)
  never appeared. Cosmetic only; every real step verified directly:
  `port = 48000` in `/etc/casaos/gateway.ini` (line 8, persists reboots),
  /DATA tree present, docker active, UI answers on guest :48000.
- Hook DNAT initially dead for same-host access: hook called bare `nft` and the
  output-chain rule matched `oifname virbr0`, but host→own-IP traffic routes
  via `lo`. `vm/fix-portforward.sh` (user ran twice) fixed both: hardcodes
  `/usr/sbin/nft`, output rules match `oifname lo`. Idempotent; fires for the
  running VM without restart.

### 7b. Port-forward verification (DONE)
- `http://192.168.1.81:18000` → HTTP 200 (host LAN IP; works from host browser
  AND any LAN device)
- `ssh -p 10022 debian@192.168.1.81` → works (key auth)
- `127.0.0.1:18000` → deliberately NOT enabled: DNAT'ing 127.0.0.1-sourced
  packets out virbr0 requires `net.ipv4.conf.all.route_localnet=1`, which
  weakens host loopback isolation. Rejected (host safety). Use the LAN IP.
- Table `ip casaos_fw`: prerouting (iif != virbr0) + output (oif lo) DNAT +
  forward accepts; auto-added on VM start, auto-removed on VM stop.

### 8. Phase A stack wiring inside VM (DONE)
**8a. CasaOS account (DONE)** — user created admin `je` via browser wizard.
Creds in `vm/credentials.txt`; login JSON in `vm/casaos-login.json`.
**8b. App installs via CasaOS API (DONE)** — discovered the v2 AppManagement
API empirically (UI bundle → openapi client → spec):
- login: `POST /v1/users/login` → access_token (saved `vm/.casaos-token`,
  0600); send as `Authorization: <token>` header
- store catalog: `GET /v2/app_management/apps` (407 apps; dumped to
  `vm/appstore.json`)
- compose template per app: `GET /v2/app_management/apps/{id}/compose`
  (saved under `vm/appcomposes/`; contains $TZ/$PUID/$PGID/$AppID vars +
  placeholder published port)
- install: `POST /v2/app_management/compose` with `Content-Type:
  application/yaml` (JSON body = valid YAML), `?dry_run=true` validates
- installer script: `vm/install-apps.py` (interpolates TZ=Europe/Athens,
  PUID/PGID=1000, $AppID; sets webui published ports to guest map; adds
  qBit 6881 tcp+udp). All 7 validated then installed, 200 each.
Installed & verified (guest port: host port → HTTP):
qBittorrent 8085:18085→200 (+6881 tcp/udp), SABnzbd 8080:18080→303
(first-boot wizard redirect), Prowlarr 9696:19696→200, Radarr 7878:17878→200,
Sonarr 8989:18989→200, Readarr 8787:18787→200, Lidarr 8686:18686→200.
All 7 containers restart unless-stopped, configs under /DATA/AppData/<app>.

**8c. qBittorrent (DONE)** — grabbed temp password from container logs
(`docker logs qbittorrent`), set permanent admin password via WebUI API
(`POST /api/v2/app/setPreferences`), saved to `vm/credentials.txt` +
`vm/.qbittorrent-pw` (0600). Login → `SID` cookie (grep from `-D -` headers).
Default save path = `/DATA/Downloads/torrents`, persisted via
`Session\DefaultSavePath` under `[BitTorrent]` in
`/DATA/AppData/qbittorrent/config/config/qBittorrent.conf`.
Gotcha: qb rewrites the conf from memory on SIGTERM — edit only while
STOPPED (docker stop → sed → docker start), edits made before a restart
get wiped.

**8d. SABnzbd (DONE, idle until Phase B)** — completed first-boot wizard via
HTTP (`POST /wizard/one` lang=en, `POST /wizard/two` no server). API works at
root path (no url_base): `http://192.168.1.81:18080/api?mode=...&apikey=...`.
Note: API config writes are POST-only (GET = CSRF-blocked). Dirs set in
sabnzbd.ini + restart: incomplete=/downloads/usenet/incomplete,
complete=/downloads/usenet/complete (container path, bind = /DATA/Downloads).
Categories created with per-cat dirs: prowlarr, radarr, tv-sonarr, readarr,
lidarr (Readarr/Lidarr *arr validation requires non-`*` dirs for job folders).
API key + nzb key in `vm/credentials.txt`.

**8e. DNS fix inside guest (DONE — was blocking all indexers)** — ISP DNS
(192.168.122.1 → host resolver → ISP) returns empty NOERROR answers for
torrent domains (DNS poisoning). Guest /etc/resolv.conf is a
systemd-resolved symlink; netplan is the source of truth. Fixed
`/etc/netplan/50-cloud-init.yaml` nameservers → `1.1.1.1, 8.8.8.8` +
`netplan apply` + restart systemd-resolved + restart all containers.
Containers then resolved fine. This must be re-checked if the VM is ever
rebuilt from the seed (seed still has old DNS).

**8f. Stack wiring via `vm/wire-arrs.py` (DONE)** — all *arr API calls from
host through port forwards. Stages (each idempotent):
- `prowlarr-clients` — qBittorrent + SABnzbd in Prowlarr (host 172.17.0.1
  = guest docker bridge gw, containers reach each other's published ports)
- `indexers` — public torrent indexers that work headless: **YTS,
  Limetorrents, LinuxTracker** (EZTV + 1337x blocked by Cloudflare — need
  FlareSolverr, skipped; ThePirateBay def no longer ships with Prowlarr 2.x)
- `applications` — Radarr/Sonarr/Readarr/Lidarr registered in Prowlarr,
  syncLevel fullSync → indexers auto-push to the arrs (Radarr+Sonarr each
  show the movie/tv-capable indexer; Readarr/Lidarr have none — no public
  book/music trackers that pass validation, fine for Phase A)
- `arr-folders` — root folders: radarr /movies, sonarr /tv, readarr /books,
  lidarr /music (container paths; readarr/lidarr need name + default
  profile ids in the POST body)
- `arr-clients` — qBittorrent + SABnzbd in each arr with categories
  (radarr, tv-sonarr, readarr, lidarr)
- `arr-rpm` — remote path mapping in each arr: host 172.17.0.1,
  /DATA/Downloads/ → /downloads/ (qBit saves under /DATA/Downloads/torrents,
  arrs see /downloads/torrents)
- `test` — POSTs the FULL resource body to .../action/test endpoints
  (id-only bodies 500). All clients + all 3 indexers: OK.
- API quirks hit: endpoint is `applications` not `application` (404);
  command `IndexerApplicationSync` not `AppIndexerSync` (500).

**8g. End-to-end test download (DONE)** — Prowlarr manual search (LinuxTracker,
"debian netinst") → push to qBittorrent via Prowlarr API → 310 MB ISO
downloaded to /DATA/Downloads/torrents, 100% verified, seeding (stalledUP).
Full chain works: search → grab → download → file on disk.

**8h. FlareSolverr + EZTV (DONE)** —
- FlareSolverr installed via CasaOS compose API (NOT in the app store;
  hand-written compose `vm/flaresolverr-compose.yaml`, `x-casaos.title`
  must be a map `en_us:` — string 500s). Container `flaresolverr`
  (ghcr.io/flaresolverr/flaresolverr:latest), guest :8191, restart
  unless-stopped.
- Prowlarr: FlareSolverr is an **indexer proxy** (not a setting):
  `POST /api/v1/indexerproxy` with schema from `/indexerproxy/schema`,
  host `http://172.17.0.1:8191`. CRITICAL: proxies apply by **tag match** —
  created tag `fs` (id 1), tagged both the proxy and the indexers; empty
  tags = applies to nothing (verified empirically).
- EZTV: added with tag → FS solved the Cloudflare challenge → validation
  passed → synced to Sonarr ("EZTV (Prowarr)"). Manual search returns
  results (TV only — it's an RSS/EZTV catalogue).
- 1337x: still blocked even through FS 3.5.0 (managed challenge too hard).
  Not installed. Would need FS v21+ fork or manual cookies — not worth it.
- Sync command name (Prowlarr 2.3.5): `ApplicationIndexerSync` (older
  `AppIndexerSync`/`IndexerApplicationSync` → 500).

**8i. Host-IP independence (DONE, DHCP-safe by design)** —
- The nft hook matches on **port + interface only** (prerouting
  `iifname != virbr0`, output `oifname lo`) — no destination-IP pinning,
  so the stack works whatever IP the host has. Proof: `P71.local` resolves
  to multiple host IPs (incl. docker0 172.17.0.1) and :18000 answers on
  all of them.
- Use `http://P71.local:<port>` (avahi mDNS, active on host) in bookmarks
  — survives DHCP changes. `bash vm/current-urls.sh` prints the full table.
- Guest/containers reference only 172.17.0.1 (the GUEST's docker bridge)
  and 192.168.122.x (libvirt net) — zero host-IP coupling.
- Re-runnable scripts now take `RRR_HOST` env override (default
  192.168.1.81): vm/wire-arrs.py, vm/install-apps.py.
- 127.0.0.1 still deliberately NOT supported (route_localnet safety).

**8j. Host DNS (DONE — user ran it)** — ISP DNS poisons
torrent domains (empty NOERROR, see §8e). `vm/fix-host-dns.sh` (NetworkManager
"con mod ipv4.dns 1.1.1.1 8.8.8.8 + ignore-auto-dns yes" on "Wired connection
1", DHCP kept for the address) — applied, connection re-upped cleanly.
Verified: /etc/resolv.conf → 1.1.1.1 + 8.8.8.8; 1337x.to now returns
real Cloudflare IPv6 (2606:4700::/…) instead of empty answers;
google.com ping 0% loss. Reverse if ever needed:
`nmcli con mod "Wired connection 1" ipv4.dns '' ipv4.ignore-auto-dns no`
+ `nmcli con up`. Guest fixed independently earlier (netplan).

## VPN notes (user runs VPN on host while VM downloads)
- Guest egress NATs through the host: full-tunnel VPN (WireGuard-style
  policy routing) carries the VM's traffic too — desired. Split-tunnel
  leaves it on the LAN gateway — also fine.
- A VPN killswitch that DROPs all non-tunnel output will cut the VM's
  internet. Test after installing any VPN.
- Browser→VM access is LAN-local, unaffected by VPN.
- qBittorrent stays reachable for seeding via outbound-initiated peers
  even when the host has no inbound forwarding (16881 is open on LAN only).
- Some VPNs hijack DNS (incl. 1.1.1.1→their resolver); guest poisoning
  risk re-appears only if the VPN resolver poisons too (rare — test with
  `getent hosts eztvx.re` in guest).

## Open items (post-Phase-A)
All details + how-to in **NEXT_STEPS_UPGRADES.md**. Summary:
- DONE: `vm/fix-host-dns.sh` run by user — host DNS on 1.1.1.1/8.8.8.8 (§8j)
- DONE since: FlareSolverr installed + EZTV working via it (§8h);
  host-IP independence verified + P71.local bookmarks (§8i)
- Readarr/Lidarr indexers: MAM (books, application-gated, free) /
  Rutracker (music, free registration) — user action needed
- Phase B (usenet): provider account → SABnzbd server → Prowlarr usenet
  indexers (Binsearch/NZBIndex free start)
- 1337x: abandoned (CF block > FlareSolverr capability)

## Rollback / teardown (host stays clean)
- VM: `sg libvirt -c "virsh destroy casaos-vm && virsh undefine casaos-vm --nvram"`
  then `rm -rf ~/VMs/casaos`
- Hook rules: removed automatically on VM stop (`nft delete table ip casaos_fw`);
  delete `/etc/libvirt/hooks/qemu` for permanence
- Daemons/packages: `sudo systemctl disable --now virtqemud virtnetworkd` +
  `sudo zypper remove libvirt-daemon-qemu libvirt-daemon-driver-network libvirt-daemon-config-network`
- Groups: `sudo gpasswd -d je libvirt && sudo gpasswd -d je kvm`
