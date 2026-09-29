# MACHINES.md — per-machine profile sets (A/B/C…)

The stack is machine-agnostic: **one functional copy** of every script lives in `vm/`,
and everything machine-specific is a small **profile set** under `machines/`. Selecting
a set wires the right values in everywhere; anything a set leaves empty is autodetected
at runtime (default-route NIC, its IP, the active NetworkManager connection).

## Sets

| Set | Machine | Status | Profile |
|---|---|---|---|
| **A** = `P71` | original host, openSUSE Leap 16, wired `enp0s31f6` | retired (as-built in git `1cc753e`) | `machines/P71/` |
| **B** = `ailab` | current host, Ubuntu 24.04, WiFi `wlp71s0` | **live** | `machines/ailab/` |
| **C…** = `TEMPLATE` | your next machine | fill in + activate | `machines/TEMPLATE/` |

## Select before you act

```bash
bash vm/select-machine.sh status        # what's active + resolved values
bash vm/select-machine.sh ailab         # activate set B (or P71, or your own)
bash vm/select-machine.sh new kitchen   # create set C from TEMPLATE
```

Selection does three things: points `machines/current` at the set, syncs the set's
`network-config` (guest MTU + DNS order) into `vm/` (old copy → `.backup`), and prints
the still-needed sudo steps. It's per-checkout runtime state (`machines/current` is
gitignored) — each machine selects once after cloning.

## What differs across machines (and where it lives)

| Concern | Where the per-machine value lives | A: P71 | B: ailab | C: new |
|---|---|---|---|---|
| OS flavor / libvirt model | `machine.env` `M_OS` (+ NOTES) | openSUSE, modular daemons | Ubuntu, monolithic + override | — |
| Host prep script (sudo, fresh host) | `machine.env` `M_HOST_PREP` | `setup_host_OpenSuseOS.sh` | `setup_host_Ubuntu.sh` | either/adapt |
| Uplink NIC + NM connection | `M_LAN_IF_DEFAULT` / `M_NM_CONN` | `enp0s31f6` / "Wired connection 1" | `wlp71s0` / "Eagle6" | autodetect |
| LAN IP fallback | `M_LAN_IP_DEFAULT` | 192.168.1.81 | 192.168.1.66 | autodetect |
| Browser URL host | `M_URL_HOST` + `M_MDNS_OK` | `P71.local` (mDNS OK) | **192.168.1.66 only** (mDNS poisoned by docker bridges) | test → choose |
| Guest NIC MTU (seed) | `M_GUEST_MTU` + set's `network-config` | — (1500) | 1280 | DF-ping bisect |
| Guest DNS order (seed) | set's `network-config` | 1.1.1.1 first (ISP poisoned host chain) | host dnsmasq first (follows Surfshark) | see TEMPLATE/NOTES |
| VM disk/data dir | `RRR_DISKDIR` env (default in `build-vm.sh`) | default | default | set if different |
| SSH keys for the guest | `vm/user-data` (shared, multi-key) | — | — | append yours |

**Deliberately NOT per-machine** (auto-detecting or guest-internal, shared as-is):
the port-forward + MSS-clamp hook (`/etc/libvirt/hooks/qemu`, installed by
`finish-host-setup.sh` — derives host IP/NIC from the default route at every VM
start), the guest static IP `192.168.122.50`, all app wiring (`wire-arrs.py`,
`install-apps.py`, compose files), credentials, `vm-power.sh`, `check-vm.sh`,
and the desktop launcher icon (`vm/desktop-icon.sh` — the installed
`~/.local/bin/rrrs-vm-start` resolves the LAN IP from the active set at click
time).

## Run order on any machine (full build)

```bash
bash vm/select-machine.sh <set>         # 0. activate the profile
sudo bash <M_HOST_PREP>                 # 1. packages/daemons/groups (from the set)
sudo bash vm/finish-host-setup.sh       # 2. port-forward + MSS-clamp hook
bash vm/build-vm.sh                     # 3. seed.iso (set's network-config) + VM launch
bash vm/check-vm.sh                     # 4. poll until provisioned
# 5..12: REBUILD.md steps 4–13 (CasaOS account, apps, keys, wiring)
```

Day-2 use needs none of the above — the desktop icon (`bash vm/desktop-icon.sh`
to install it) or `vm/vm-power.sh start`, + the URLs from `vm/current-urls.sh`
(already profile-aware).

## VPN (Surfshark) — no per-machine config

Verified on ailab 2026-09-29 (details in `machines/ailab/NOTES.md`): Surfshark's
policy routing carries the VM's NATed traffic automatically (VM egress == host
egress == exit node), services stay reachable, and the guest's primary DNS follows
the host resolver, which Surfshark rewrites while connected. Toggle the app; done.
On a new host, re-verify with the two `api.ipify.org` curls in the set NOTES.
