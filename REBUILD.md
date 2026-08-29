# REBUILD.md — Rebuild the RRRs stack on a different machine

Runbook for reproducing the whole stack (KVM VM + CasaOS + Prowlarr/Radarr/
Sonarr/Readarr/Lidarr/SABnzbd/qBittorrent + FlareSolverr) from this repo
alone. Read `NOTES-PROGRESS.md` alongside — it has every gotcha hit on the
original build. `RRR-PLAN.md` is the original planning doc; `HOWTO-USE.md`
describes daily use of the finished stack.

## Host requirements

- x86_64 Linux with KVM, plus: libvirt, qemu, `virt-install`, `mkisofs`
  (genisoimage), `curl`, `sshpass`, `python3` (stdlib only).
- The original host was **openSUSE Leap 16.0**. The host scripts use zypper
  and the *modular* libvirt daemon names (`virtqemud`, `virtnetworkd` + the
  5 companion socket daemons). On another distro, install the equivalents
  (libvirt + qemu-kvm + virtinst + genisoimage) and make sure the QEMU
  driver daemon, the network daemon, and the companion daemons
  (storage/log/lock/secret/nodedev) are running; monolithic `libvirtd`
  distros just need `libvirtd` running. The end state that matters:
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

If the host IP is not `192.168.1.81`, export `RRR_HOST=<ip>` for every
script below (install-apps.py, wire-arrs.py, collect-keys.sh).

## Steps

### 1. Base image (not in git — it's the 430 MB gitignored file)

```bash
bash vm/get-base-image.sh
```

Downloads the pinned build **Debian 12 bookworm 20260806-2562**
(`https://cdimage.debian.org/cdimage/cloud/bookworm/20260806-2562/`) and
SHA512-verifies it against `vm/SHA512SUMS` (the build's official manifest,
filenames normalized). Idempotent.

### 2. Host prep (run with sudo; openSUSE: `zypper install qemu virt-install` first)

```bash
sudo bash vm/setup-host.sh        # packages (zypper), daemons, default net, group membership
sudo bash vm/finish-host-setup.sh # companion sockets + port-forward hook (/etc/libvirt/hooks/qemu)
```

Log out and back in afterwards (group membership). On a non-openSUSE host
adapt the zypper/systemctl lines to the equivalent packages/units — the
hook in step 2b is distro-agnostic.

### 3. Build + provision the VM

```bash
bash vm/build-vm.sh
```

Creates `~/VMs/casaos/system.qcow2` (32 G overlay on the base image) and
`data.qcow2` (200 G sparse), rebuilds `seed.iso` from the NoCloud seed files,
launches `casaos-vm` via `virt-install`. Then poll:

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

```bash
python3 - <<'PY'
import json, os, re, urllib.request
host = "192.168.1.81"  # or your RRR_HOST
txt = open("vm/credentials.txt").read()
pw = re.search(r"^CasaOS admin password: (.+)$", txt, re.M).group(1).strip()
body = json.dumps({"username": "je", "password": pw}).encode()
r = urllib.request.urlopen(urllib.request.Request(
    f"http://{host}:18000/v1/users/login", data=body,
    headers={"Content-Type": "application/json"}), timeout=15)
tok = json.load(r)["access_token"]
open("vm/.casaos-token", "w").write(tok)
os.chmod("vm/.casaos-token", 0o600)
print("token saved to vm/.casaos-token")
PY
```

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
useless until it's done. Complete it headlessly (NOTES §8d): `POST
/wizard/one` with `lang=en`, then `POST /wizard/two` with no server — or
just click through `http://<host>:18080`. (No usenet server in Phase A;
that's deliberate.)

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

## Not reproducible from the repo (by design)

- `~/VMs/casaos/{system,data}.qcow2` — created by build-vm.sh; the data
  disk holds all media + app configs and starts empty.
- `~/.ssh/id_ed25519` — only the PUBLIC key is baked into `vm/user-data`
  (original host's key). On a fresh host use the password from
  `vm/credentials.txt`; `check-vm.sh` falls back to sshpass automatically.
- Port-forward hook rules — reinstalled automatically on every VM start by
  the hook; removed on stop. Nothing to do.

## Gotchas index (details in NOTES-PROGRESS.md)

- Modular libvirt: companion daemon sockets must be up (finish-host-setup.sh).
- qBittorrent rewrites its config from memory on SIGTERM — never edit
  `/DATA/AppData/qbittorrent/.../qBittorrent.conf` while it runs.
- `cloud-init status` may report "running" forever (deadlock in the seed's
  last runcmd) — cosmetic; verify the real steps directly.
- 127.0.0.1:port on the host deliberately does NOT work (route_localnet
  not enabled) — use the host's LAN IP.
- `x-casaos.title` in compose must be a map (`en_us:`), a plain string 500s.
- Prowlarr indexer proxies apply by TAG match — the `fs` tag must exist and
  be on both proxy and indexer (handled by the flare-solverr stage).
