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

## Phase B: Dynamic host detection (remove remaining hardcoded values)

Values now target **ailab** (192.168.1.66, wlp71s0, Eagle6). Remaining
hardcodes that would need adapting on a *third* machine:

### NIC detection (partially done)
- [ ] `fix-host-dns.sh`: NM connection hardcoded to "Eagle6" → query NM for
      the active internet-facing connection
- [ ] `current-urls.sh`: interface hardcoded to wlp71s0 → detect default-route
      interface (`ip -4 route show default`)
- [x] Port-forward hook: host IP + interface auto-detected from default route
- [x] `network-config`: `en*s*` wildcard — works everywhere; guest MTU 1280 set

### Host IP detection (defaults updated, not dynamic)
- [x] `install-apps.py` / `wire-arrs.py` / `collect-keys.sh` /
      `get-casaos-token.sh`: fallback IP updated to 192.168.1.66 (RRR_HOST
      still overrides) — fallback remains a hardcode, detection approach:
      `ip -4 route show default | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}'`

### Libvirt model detection
- [x] `setup_host_Ubuntu.sh` detects modular vs monolithic and acts per model

### SSH key in user-data
- [x] Second key (je@ailab) appended; supports any number of keys
- [ ] Auto-inject the building host's `~/.ssh/id_ed25519.pub` during build

### DNS fix script
- [ ] `fix-host-dns.sh` still needs the exact NM connection name; make it
      query active connections with a default route
