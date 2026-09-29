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

## 2026-09-19/20 — Rebuild on ailab (Ubuntu 24.04, WiFi host)

Full rebuild from this repo. Four environment differences bit; all fixes are
baked into the scripts now (details in REBUILD.md gotchas):

1. **libvirtd `--timeout 120` + socket activation** (Ubuntu default): daemon
   self-exits when idle, next activation refuses to re-adopt the running
   network → `net-start` fails EADDRINUSE against orphaned dnsmasq sockets
   (the "ghost dnsmasq" mess; explains recurring 21:56-era orphans). Fix:
   drop-in `/etc/systemd/system/libvirtd.service.d/override.conf` blanking
   `LIBVIRTD_ARGS` → persistent daemon. Encoded in `setup_host_Ubuntu.sh`,
   which also cleans ghosts + orphan virbr0 + the session-daemon phantom
   `default` network before starting the real one.
2. **Session-vs-system virsh**: non-root `virsh` defaults to `qemu:///session`
   whose phantom state readings derailed diagnostics for a while. All scripts
   now use explicit `--connect qemu:///system`.
3. **WiFi uplink path MTU is 1280** (DF-ping bisect: 1252 payload OK, 1272
   FAIL). Host TCP survives via its own PMTUD; guests behind NAT never get
   the ICMP → large packets blackhole, apt stalls in infinite retries while
   SSH/DNS/handshakes all "work". Fix (two layers, both permanent): guest NIC
   MTU 1280 in `vm/network-config` + MSS clamp 1240 in the port-forward hook.
4. **nft syntax drift**: MSS clamp is `tcp option maxseg SIZE set 1240` on
   current nft (Ubuntu 24.04); the old wiki form `target set` is a parse
   error — and the hook (no `set -e`) swallowed it silently, so the rules
   were simply missing. Hook now wipes-then-adds (idempotent) and
   `finish-host-setup.sh` applies rules live when the VM is already running
   (no more destroy/start dance after hook edits).

**Storage redesign — virtiofs**: `/DATA` is no longer a 200G `data.qcow2`;
it's a virtiofs share of `/home/je/NVMe4TB/RRRs_VM/RRRs_DATA/` (plain host
files; browsable/backupable without the VM; survives system rebuilds by
construction). Requires `virtiofsd` package (now in setup_host_Ubuntu.sh).
build-vm.sh: `--filesystem type=mount,driver.type=virtiofs,...` +
`--memorybacking source.type=memfd,access.mode=shared` (virt-install 4.1
does NOT auto-add shared memory). Verified: guest-write → host-file
round trip instant.

**CasaOS v0.4.15 login shape**: JWT at `data.token.access_token` (nested,
envelope `{"success":200,...}`) — NOT top-level `access_token`. Handled in
`vm/get-casaos-token.sh` (hidden password prompt; username via
`RRR_CASAOS_USER`, default `je`).

**Host-local browser access**: packets to the host's own IP route via `lo`,
so the hook's `oifname "virbr0"` output rules never matched them — UI was
reachable only from OTHER LAN devices. Hook now DNATs `ip daddr $HOST_IP`
traffic too, host IP auto-detected from the default-route interface
(survives WiFi↔wired moves).

**cloud-init seed fix**: the old last runcmd (`cloud-init status --wait`
inside the final stage) deadlocks — status stays "running" forever (§7-era
"cosmetic" issue, root-caused this time). Current seed writes
`/root/PROVISION_DONE.txt` (df + date) and `check-vm.sh` reads it via sudo.

**Verified end state**: cloud-init done; casaos/casaos-gateway/docker active;
8 containers up (7 arrs + flaresolverr); host browser `:18000` → 200; SSH
forward `:10022` banner OK; token flow OK; dry-run install 7×200 + real
install accepted.

Ubuntu teardown equivalent: same virsh lines, plus
`sudo systemctl disable --now libvirtd` and `sudo apt-get purge
libvirt-daemon-system qemu-kvm virtinst` (remove the drop-in override at
`/etc/systemd/system/libvirtd.service.d/` too). Data survives in
`RRRs_DATA/` — delete manually only if intended.

## 2026-09-20 ailab: full service (Phase A complete)

Everything from "Remaining to full service" done in one session. All state
below is the live VM; keys in `vm/credentials.txt` are current.

**qBittorrent** — temp creds via `sudo docker logs qbittorrent` (guest debian
user is NOT in the docker group — every `docker` call needs sudo there).
Password set to the `vm/credentials.txt` value via
`POST /api/v2/app/setPreferences` (`json={"web_ui_password":...}`) and
re-login-verified; also re-saved to `vm/.qbittorrent-pw` (0600). Default
save path set via the same call (`json={"save_path":"/DATA/Downloads/torrents"}`).
Gotcha rediscovered: fresh qBit config defaults to `/app/qBittorrent/downloads`;
the container mounts the WHOLE `/DATA` at `/DATA`, so the save path is the
guest path verbatim. API setPreferences survives the SIGTERM conf rewrite.

**SABnzbd headless wizard** — `POST /wizard/one` (`lang=en`), then
`POST /wizard/two` WITH the `ssl=0` field (server-side requires the key even
when skipping the usenet server; first attempt without it silently re-rendered
the form). Two extra steps beyond the wizard POSTs:
1. `wizard_complete = 1` + `complete_dir=/downloads/usenet/complete` +
   `incomplete_dir=/downloads/usenet/incomplete` written into
   `/config/sabnzbd.ini` + restart (dir layout per §8b/NOTES 22).
2. SAB 5.x STILL 303-redirects `/` → `/wizard/` while
   `config.get_servers()` is empty (interface.py ~L455). Phase A has no
   usenet server, so a disabled placeholder was appended:
   `[servers]/[[placeholder]] host=none.invalid, enable=0`. Root now 200.
Categories recreated via API (original VM had them; fresh /config lost them):
`POST /api?mode=set_config&section=categories&name=<cat>&dir=/downloads/usenet/complete/<cat>`
for prowlarr, radarr, tv-sonarr, readarr, lidarr. CherryPy gotcha: POST with
no body → HTTP 411; `curl -d ''` supplies Content-Length.

**collect-keys.sh fixes (fresh-build flow)** — three bugs vs the 2026 stack:
- guest docker needs `sudo docker exec` (added at all 3 call sites)
- ALL five *arrs keep their key in `/config/config.xml` `<ApiKey>` — the
  `*.conf` JSON paths never existed in these images; everything uses xmlkey now
- sshpass isn't installed on ailab: script now probes key auth first
  (`ssh -o BatchMode=yes`), falls back to sshpass + VM password
Fresh keys applied to `vm/wire-arrs.py` APPS/SAB_APIKEY and credentials.txt.

**wire-arrs.py drift fixes (Prowlarr 2.3.5)** —
- tags: API wants `label`, not `name` (400 "Label must not be empty")
- FlareSolverr proxy schema: single full-URI `host` field
  (`http://172.17.0.1:8191`), port/useSsl fields are gone
- Limetorrents dropped from INDEXERS: definition targets `.fun` (dead,
  connection refused), `.com` →301→ `.pro` →302→ `ww1.` parked page
- sync command works as-is now; Readarr/Lidarr show 0 indexers — matches
  the original build exactly (no public book/music trackers pass validation)

**End-to-end test (§13/§8g replicated)** — Prowlarr API search (LinuxTracker,
"debian") → smallest result (debian-mac-13.7.0-amd64-netinst.iso, 757 MB)
→ `POST /api/v1/search` grab body `{guid, indexerId, downloadClientId: 1,
downloadClient: "qBittorrent"}` → qBittorrent downloaded at ~38 MB/s to
`/DATA/Downloads/torrents` (host: `RRRs_DATA/Downloads/torrents/`), 100%,
seeding (stalledUP). First grab landed in the wrong dir (pre-save_path-fix);
deleted with `deleteFiles=true` and re-grabbed. Search quirk: "debian netinst"
(two tokens) returns 0 hits on LinuxTracker; single-token "debian" works.

## 2026-09-29 — ailab: machine-profile refactor + Surfshark verification

**Surfshark live-verified (tunnel up)** — client 3.13 (WireGuard `surfshark_wg` +
`surfshark_ipv6`), policy routing `not from all fwmark 0x493e0 lookup 300000`
+ `suppress_prefixlength 0` on main: every unmarked packet — including the VM's
NATed flows — enters the tunnel. Measured: host egress 185.9.16.102 ==
guest egress 185.9.16.102 (identical exit); all 8 services HTTP 200 with the
tunnel up (kill switch, whatever its state, does not cut forwarded VM traffic
or LAN access). Host resolver flips to Surfshark-pushed resolvers
(162.252.172.57, 149.154.159.92, 151.236.14.64) on connect; the guest's
PRIMARY resolver is 192.168.122.1 → host dnsmasq → host resolver, so
VPN on = guest uses Surfshark DNS, VPN off = 1.1.1.1. No leak path (both
resolver routes ride the tunnel). Zero extra configuration required.

**Machine-profile refactor** — repo restructured into per-machine SETS so a
third machine is "select and go" (spec + matrix in MACHINES.md):
- `machines/P71/` (set A, retired host, values as-built: openSUSE/enp0s31f6/
  "Wired connection 1"/192.168.1.81/P71.local/mDNS OK/1500)
- `machines/ailab/` (set B, live: Ubuntu/wlp71s0/Eagle6/192.168.1.66/IP-only
  — mDNS poisoned by docker+calico bridges registering with avahi, `ailab.local`
  resolves to 172.17.0.1 — /guest MTU 1280/DNS follows host chain for Surfshark)
- `machines/TEMPLATE/` (set C scaffolding + value-derivation cheatsheet)
- `vm/select-machine.sh {P71|ailab|new <name>|status}`: points `machines/current`
  (gitignored symlink) at a set, syncs the set's `network-config` into `vm/`
  (.backup kept), prints resolved values + sudo reminders
- `vm/_machine.sh` (bash) / `vm/_rrrhost.py` (python): shared resolvers —
  env `RRR_*` > set's machine.env > autodetect (default-route iface/IP, active
  NM connection). current-urls.sh (now mDNS-aware), fix-host-dns.sh,
  collect-keys.sh, wire-arrs.py, install-apps.py, get-casaos-token.sh all
  consume them; build-vm.sh takes `RRR_DISKDIR` + prints the active set
- functional `vm/network-config` = ailab variant (as-running: mtu 1280,
  122.1-first DNS); P71 variant = 1.1.1.1-first (its poisoning history)
- docs: HOWTO-USE URLs per machine + Surfshark section; REBUILD.md step 0;
  TODO Phase B closed. Pre-edit copies of every touched file left as `*.backup`
  (gitignored).

### Desktop icon (one-click start + tabs)

New: `vm/desktop-icon.sh` — installs `~/.local/bin/rrrs-vm-start` +
`rrrs-media-vm.desktop` (Desktop + applications menu). Double-click = start VM
if off → wait for :18000 (3 min cap) → open all 8 web UIs as Firefox tabs;
menu actions "Start VM only" / "Open web UIs only". LAN IP resolved at click
time via `_machine.sh` (follows machine set, no reinstall).
Tested e2e on ailab (KDE Plasma X11, snap Firefox 156): icon cold-started the
shut-off VM, all 8 ports 200 at t+33 s, tabs confirmed in Firefox's session
snapshot (`recovery.jsonlz4` rewritten containing the URLs); `tabs` and
`start` actions exit 0. Targets Ubuntu 24.04 (verified) + openSUSE Leap 15.6
(standard .desktop/firefox mechanism; GNOME gets a `gio` trust flag, KDE
launches via +x). UNTESTED: Leap 15.6 runtime.
