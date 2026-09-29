# REBUILD.md — Rebuild the RRRs stack on a different machine

Runbook for reproducing the whole stack (KVM VM + CasaOS + Prowlarr/Radarr/
Sonarr/Readarr/Lidarr/SABnzbd/qBittorrent + FlareSolverr) from this repo
alone. Read `NOTES-PROGRESS.md` alongside — it has every gotcha hit on the
original build. `RRR-PLAN.md` is the original planning doc; `HOWTO-USE.md`
describes daily use of the finished stack.

## Host requirements

- x86_64 Linux with KVM, plus: libvirt, qemu, `virt-install`, `mkisofs`
  (genisoimage), `curl`, `sshpass`, `python3` (stdlib only), `virtiofsd`
  (the /DATA shared-folder daemon; Ubuntu package `virtiofsd`).
- Two supported host scripts: `setup_host_Ubuntu.sh` (Ubuntu/Debian,
  monolithic `libvirtd`, apt) and `setup_host_OpenSuseOS.sh` (original host,
  modular daemons, zypper). The end state that matters:
  - `virsh` works for the operator user **without sudo** (user in the
    `libvirt` + `kvm` groups; scripts call `sg libvirt -c "virsh ..."`),
  - the `default` NAT network (192.168.122.1/24) is active + autostart,
  - `/etc/libvirt/hooks/qemu` is installed (step 2 below does this).
- Ports free on the host: 10022, 18000, 19696, 17878, 18989, 18787, 18686,
  18080, 18085, 16881.
- The guest gets a static **192.168.122.50** on the libvirt `default`
  network — standard on any host, nothing to configure.
- RAM: give the VM 8 GB / 4 vCPUs as in `vm/build-vm.sh` (or less; the stack
  idles around 1.5 GB but torrent-heavy use likes headroom).

Machine-specific values (LAN IP, NIC, NM connection, URL host, guest MTU, DNS
order) live in **machine profile sets** — `machines/P71` (set A, original host,
192.168.1.81 wired), `machines/ailab` (set B, current host, 192.168.1.66 WiFi),
`machines/TEMPLATE` (set C — derive + activate for any new host). See
`MACHINES.md`. Selecting a set (`bash vm/select-machine.sh <set>`, step 0 below)
removes the need for `RRR_HOST` exports: scripts resolve host IP as
env `RRR_HOST` > the set's `M_LAN_IP_DEFAULT` > autodetect (default-route src).

**Network MTU note:** the primary host's WiFi uplink has a path MTU of 1280
(verified by DF-ping bisect). This is handled in two layers — guest NIC MTU
1280 in `vm/network-config`, and an MSS-clamp (1240) in the port-forward
hook. On a host with a clean 1500 path both are harmless belt-and-suspenders.
Without them, guests behind the NAT stall forever on large packets (PMTUD
ICMP never reaches them).

## Steps

### 0. Select the machine profile (new machines: create one first)

Fresh clone: credential files are git-crypt-encrypted — unlock first with the
repo key (kept OUT of git, e.g. `~/git-crypt-keys/RRRs.key`):
`git-crypt unlock ~/git-crypt-keys/RRRs.key`

```bash
bash vm/select-machine.sh status            # already selected on an existing checkout
bash vm/select-machine.sh new <name>        # NEW host only: copy TEMPLATE, fill machine.env (NOTES.md there)
bash vm/select-machine.sh <P71|ailab|name>  # activate
```

### 1. Base image (not in git — it's the 430 MB gitignored file)

```bash
bash vm/get-base-image.sh
```

Downloads the pinned build **Debian 12 bookworm 20260806-2562**
(`https://cdimage.debian.org/cdimage/cloud/bookworm/20260806-2562/`) and
SHA512-verifies it against `vm/SHA512SUMS` (the build's official manifest,
filenames normalized). Idempotent.

### 2. Host prep (run with sudo)

**Ubuntu/Debian:**
```bash
sudo bash vm/setup_host_Ubuntu.sh        # packages, daemons, default net, group membership
sudo bash vm/finish-host-setup.sh        # companion sockets + port-forward hook (/etc/libvirt/hooks/qemu)
```

**openSUSE Leap (original host):**
```bash
sudo bash vm/setup_host_OpenSuseOS.sh    # zypper install, modular libvirt daemons
sudo bash vm/finish-host-setup.sh        # companion sockets + port-forward hook (/etc/libvirt/hooks/qemu)
```

Log out and back in afterwards (group membership). On a non-openSUSE host
adapt the zypper/systemctl lines to the equivalent packages/units — the
hook in step 2b is distro-agnostic.

### 3. Build + provision the VM

```bash
bash vm/build-vm.sh
```

Creates `/home/je/NVMe4TB/RRRs_VM/system.qcow2` (32 G overlay on the base
image), rebuilds `seed.iso` from the NoCloud seed files, launches
`casaos-vm` via `virt-install`. **`/DATA` is not a disk**: it's a virtiofs
share of `/home/je/NVMe4TB/RRRs_VM/RRRs_DATA/` on the host (plain files —
browsable, backupable, host-app-visible while the VM runs; survives system
rebuilds). Requires the `virtiofsd` package on the host (step 2 installs
it). Then poll:

```bash
bash vm/check-vm.sh    # repeat every ~30s
```

Provisioning takes ~5–10 min: cloud-init runs the official CasaOS installer
(`curl get.casaos.io | bash`), forces the gateway to port 48000, builds the
`/DATA` tree. The VM **reboots itself once** after install — normal
(NOTES §7). Done when `casaos-gateway` + `casaos` + `docker` are active and
guest :48000 answers.

Note: `build-vm.sh` sets `--autostart`. The original host has autostart
disabled (user preference) — if you want that, `virsh autostart --disable
casaos-vm` after provisioning.

### 4. First CasaOS account — the only manual/browser step

Open `http://<host-ip>:18000` and create the first account with username
**`je`** and the password from `vm/credentials.txt` (line `CasaOS admin
password:`). The username and password **must match that file exactly** —
steps 6 and 8 depend on them.

### 5. Set the qBittorrent admin password

```bash
ssh -p 10022 debian@<host-ip>        # password: 'SSH password:' in vm/credentials.txt
docker logs qbittorrent 2>&1 | grep -iE "username|password"
```

Log into `http://<host-ip>:18085` with the temporary credentials printed in
the logs, then change the admin password to **exactly** the qBittorrent
password in `vm/credentials.txt` (wire-arrs.py hardcodes it).

### 6. Get the CasaOS API token (replaces the stale `vm/.casaos-token`)

v0.4.x has **no API-key field in the UI** — the token is issued by the login
endpoint. Run the helper (prompts for the password, hidden; username defaults
to `je`, override with `RRR_CASAOS_USER=<name>`):

```bash
bash vm/get-casaos-token.sh
```

It POSTs `{"username","password"}` to `/v1/users/login` and saves
`vm/.casaos-token` (0600). Response shape (v0.4.15): the JWT is at
`data.token.access_token` — nested, not top-level; the helper handles it.

### 7. DNS (only if the ISP poisons torrent domains)

Test inside the guest: `getent hosts eztvx.re` (if google.com resolves but
this doesn't, you're being poisoned — the original ISP was). Fix:

- Guest: set `/etc/netplan/50-cloud-init.yaml` nameservers to `1.1.1.1,
  8.8.8.8` → `netplan apply` → restart systemd-resolved + all containers
  (NOTES §8e).
- Host: `sudo bash vm/fix-host-dns.sh` (NetworkManager-specific; adapt for
  other resolvers — goal is static 1.1.1.1/8.8.8.8 on the uplink).

Skip if your DNS is clean.

### 8. Install the 7 apps

```bash
python3 vm/install-apps.py --dry-run-only   # all 7 should say 200
python3 vm/install-apps.py
```

Uses the stored compose templates in `vm/appcomposes/` via the CasaOS v2
AppManagement API (token from step 6). Verifies each webui port afterwards
(HOWTO-USE.md URL table, guest ports).

### 9. Install FlareSolverr (Cloudflare bypass for EZTV)

```bash
curl -s -X POST "http://$RRR_HOST:18000/v2/app_management/compose" \
  -H "Content-Type: application/yaml" \
  -H "Authorization: $(cat vm/.casaos-token)" \
  --data-binary @vm/flaresolverr-compose.yaml
```

Check the `flaresolverr` container is up on guest :8191.

### 10. Complete the SABnzbd first-boot wizard

A fresh SABnzbd answers :18080 with a 303 to the wizard and its API is
useless until it's done. Headless: `POST /wizard/one` with `lang=en`, then
`POST /wizard/two` with empty server fields but MUST include `ssl=0` (the
server-side validator requires the key; omitting it silently re-renders
the form) plus the hidden `apikey` value from the form HTML — or just click
through `http://<host>:18080`. Three follow-ups are REQUIRED (details in
NOTES "2026-09-20 ailab: full service"): set `wizard_complete=1` and the
usenet complete/incomplete dirs in `/config/sabnzbd.ini` + restart, add a
disabled placeholder `[servers]` entry (SAB 5.x keeps 303-redirecting `/`
to the wizard while zero servers exist), and create the 5 categories via
`set_config&section=categories` (Prowlarr validates them when saving the
SABnzbd download client). No usenet server in Phase A; that's deliberate.

### 11. Collect the fresh API keys — REQUIRED, the committed keys are dead

Every app generated new keys at first boot. Run:

```bash
bash vm/collect-keys.sh
```

and apply the printed edits to `vm/wire-arrs.py` (APPS dict + SAB_APIKEY)
and `vm/credentials.txt`. Without this, step 12 fails on every auth call.

### 12. Wire the stack (order matters)

```bash
python3 vm/wire-arrs.py --stage prowlarr-clients
python3 vm/wire-arrs.py --stage flare-solverr
python3 vm/wire-arrs.py --stage indexers
python3 vm/wire-arrs.py --stage applications
python3 vm/wire-arrs.py --stage arr-folders
python3 vm/wire-arrs.py --stage arr-clients
python3 vm/wire-arrs.py --stage arr-rpm
python3 vm/wire-arrs.py --stage sync
python3 vm/wire-arrs.py --stage test
python3 vm/wire-arrs.py --stage verify
```

All `test` lines should say OK. `verify` should show indexers in Radarr/
Sonarr (movie/TV-capable ones), none in Readarr/Lidarr (no public
book/music trackers pass validation — expected, NOTES §8f).

### 13. End-to-end check

Prowlarr UI (`:19696`) → Interactive Search (e.g. LinuxTracker, "debian
netinst") → download icon → qBittorrent → confirm it lands in
`/DATA/Downloads/torrents` (CasaOS Files, `:18000`). That's the §8g test.

### Afterwards (optional): one-click desktop icon

`bash vm/desktop-icon.sh` installs a "RRRs Media VM" desktop icon — double-click
starts the VM if it's off and opens all 8 web UIs as Firefox tabs. Resolves the
LAN IP from the active machine set at click time. Details: HOWTO-USE.md.

## Not reproducible from the repo (by design)

- `/home/je/NVMe4TB/RRRs_VM/system.qcow2` — created by build-vm.sh; disposable.
  **`RRRs_DATA/` next to it is the real data** (virtiofs source for guest
  `/DATA`): media, downloads, and app configs as plain host files. It is NOT
  touched by rebuilds — delete it manually only if you mean it.
- `~/.ssh/id_ed25519` — only the PUBLIC keys are baked into `vm/user-data`
  (`je@casaos-admin` original host, `je@ailab` current host). On a fresh host
  use the password from `vm/credentials.txt`; `check-vm.sh` falls back to
  sshpass automatically.
- Port-forward hook rules — reinstalled automatically on every VM start by
  the hook; removed on stop. Nothing to do.

## Gotchas index (details in NOTES-PROGRESS.md)

- **Ubuntu socket-activated libvirtd runs with `--timeout 120`**: when the
  daemon self-exits while a network is active, the next activation refuses
  to re-adopt it and `net-start` fails EADDRINUSE against ghost dnsmasq
  sockets. `setup_host_Ubuntu.sh` installs a drop-in override that blanks
  `LIBVIRTD_ARGS` so the daemon stays persistent.
- **`virsh` without `--connect qemu:///system` talks to the SESSION daemon**
  (non-root default) — its state readings are a phantom of the real one.
  Every script here uses the explicit URI. The session daemon may also have
  its own phantom `default` network; setup removes it.
- **nftables MSS-clamp syntax**: `tcp option maxseg SIZE set 1240` on
  current nft (Ubuntu 24.04) — the old wiki form `target set` is a parse
  error. The hook uses the current form.
- Modular libvirt: companion daemon sockets must be up (finish-host-setup.sh).
- qBittorrent rewrites its config from memory on SIGTERM — never edit
  `/DATA/AppData/qbittorrent/.../qBittorrent.conf` while it runs.
- `cloud-init status` may report "running" forever if the seed's last runcmd
  calls `cloud-init status --wait` (circular). Current seed writes a plain
  marker file instead (`/root/PROVISION_DONE.txt`); older seeds had the
  deadlock.
- 127.0.0.1:port on the host deliberately does NOT work (route_localnet
  not enabled) — use the host's LAN IP (the hook DNATs host-own-IP traffic
  via auto-detected default-route interface).
- `x-casaos.title` in compose must be a map (`en_us:`), a plain string 500s.
- Prowlarr indexer proxies apply by TAG match — the `fs` tag must exist and
  be on both proxy and indexer (handled by the flare-solverr stage).
