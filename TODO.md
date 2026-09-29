# RRRs — TODO / Feature Tracker

## Phase A: Ubuntu migration (DONE 2026-09-20)

- [x] Create `setup_host_Ubuntu.sh` (replaces openSUSE-specific `setup-host.sh`)
- [x] Rename original `setup-host.sh` → `setup_host_OpenSuseOS.sh`
- [x] Fix `fix-host-dns.sh` for Ubuntu host (Eagle6 + wlp71s0)
- [x] Fix `current-urls.sh` for Ubuntu host (wlp71s0)
- [x] Add je@ailab SSH key to `vm/user-data` cloud-config
- [x] Update `REBUILD.md` with dual-host script references
- [x] Test full build on this machine (ailab / Ubuntu 24.04) — stack verified
      2026-09-20: 8 containers up, port-forwards OK, virtiofs /DATA round-trip OK
- [x] Ubuntu-specific fixes baked into scripts: persistent-libvirtd override
      (ghost-dnsmasq/network-adoption bug), session-phantom cleanup,
      MSS clamp 1240 (WiFi path MTU 1280), host-IP local DNAT in hook,
      virtiofs `/DATA` redesign (`RRRs_DATA/` host dir), live rule re-apply
      on `finish-host-setup.sh`, `get-casaos-token.sh` (v0.4.15 nested JWT)

## Phase B: Dynamic host detection (DONE 2026-09-29 — machine profile sets)

Machine-specific values moved to `machines/<set>/` profile sets (P71 = A, ailab =
B, TEMPLATE = C) — see MACHINES.md. Scripts resolve every value as
env override > selected set > autodetect:

- [x] `fix-host-dns.sh`: NM connection from the profile, autodetect fallback
      (active connection on the default-route iface) — no more "Eagle6" hardcode
- [x] `current-urls.sh`: iface/IP from the profile, autodetect fallback
      (`ip route show default`); mDNS advertised only when the profile allows
      (ailab: docker bridges poison `.local` — IP only)
- [x] `install-apps.py` / `wire-arrs.py` / `collect-keys.sh` /
      `get-casaos-token.sh`: shared `_rrrhost.py` — env `RRR_HOST` >
      set's `M_LAN_IP_DEFAULT` > autodetect (default-route src IP)
- [x] Port-forward hook: host IP + interface auto-detected from default route (was done)
- [x] `network-config`: `en*s*` wildcard everywhere; guest MTU per set
      (`M_GUEST_MTU` + set's network-config: ailab 1280, P71 default)
- [x] `select-machine.sh new <name>` scaffolds set C on a third machine
- [ ] Auto-inject the building host's `~/.ssh/id_ed25519.pub` into `vm/user-data`
      during build (for now: append it by hand before `build-vm.sh`)

## Phase C: candidates

- [x] One-click desktop icon — DONE 2026-09-29: `vm/desktop-icon.sh` (Ubuntu
      24.04 verified e2e on ailab; Leap 15.6 same mechanism, untested runtime).
      Starts the VM if off, opens all 8 web UIs as Firefox tabs. Docs:
      HOWTO-USE.md "Desktop icon".
- [ ] qBittorrent binding to the VPN interface only (so downloads stop when the
      tunnel drops) — Surfshark verified to carry the VM 2026-09-29; binding is
      a guest-side qBittorrent setting (Advanced → Network Interface) if wanted
- [ ] Auto-start the VM on a Surfshark-connected schedule (systemd timer)
