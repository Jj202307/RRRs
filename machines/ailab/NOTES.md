# SET B — ailab (current host, Ubuntu 24.04)

As-built 2026-09-20 (fresh build from REBUILD.md, e2e-tested). Current live host of the stack.

## What's different from other sets

| Value | ailab value |
|---|---|
| OS / libvirt | Ubuntu 24.04, MONOLITHIC `libvirtd` + `override.conf` blanking `LIBVIRTD_ARGS` (ghost-dnsmasq / network non-adoption bug — REBUILD.md Gotchas) |
| Host prep | `sudo bash vm/setup_host_Ubuntu.sh` (apt) + `sudo bash vm/finish-host-setup.sh` |
| Uplink | WiFi `wlp71s0`, NM connection `Eagle6`, **path MTU 1280** (DF-ping bisected) |
| Guest NIC MTU | 1280 (seed) + MSS clamp 1240 (hook) — without both, guests stall on large packets |
| Guest DNS order | host chain FIRST (`192.168.122.1`) — deliberate, see "VPN" below. `1.1.1.1` fallback |
| URL host | **raw IP `192.168.1.66` ONLY** — see mDNS trap |
| As-built LAN IP | `192.168.1.66` (DHCP; scripts autodetect anyway) |

## THE mDNS TRAP on this host (do not use *.local)

ailab runs Docker + Calico (`docker0`, `br-*`, `vxlan.calico`) and those interfaces
register with avahi. `ailab.local` resolves to `172.17.0.1` (docker0) / link-local
junk — NOT the LAN IP. The port-forward DNAT only matches the default-route IP, so
`http://ailab.local:18000` = connection refused. Always use the IP; `vm/current-urls.sh`
prints correct URLs and is mDNS-aware via this set's `M_MDNS_OK=0`.

Also: this host runs other services — check port collisions before (re)building:
`ss -tlnp | grep -E ':(10022|18000|19696|17878|18989|18787|18686|18080|18085|16881) '`

## Surfshark VPN — VERIFIED 2026-09-29 (live, tunnel up)

- Surfshark client 3.13 (WireGuard, `surfshark_wg` + `surfshark_ipv6`), policy routing:
  `not fwmark 0x493e0 lookup 300000` — catches ALL unmarked traffic including the
  VM's NATed flows. **VM egress == host egress == Surfshark exit (185.9.16.102).**
- All 8 services stayed reachable (HTTP 200) with the tunnel up — kill switch (whatever
  its setting) does not break forwarded VM traffic or LAN access.
- DNS: guest primary resolver = `192.168.122.1` → host dnsmasq → host resolver, which
  Surfshark rewrites to its pushed resolvers (`162.252.172.57`, `149.154.159.92`,
  `151.236.14.64`) while connected. VPN on = VM uses Surfshark DNS; VPN off = VM uses
  `1.1.1.1` (host pinned). No leak path: both resolvers ride the tunnel.
- Zero extra config required. Just toggle the app.

## Functional locations on this machine (host = ailab)

- `/etc/libvirt/hooks/qemu` — port-forward + MSS-clamp hook (installed; auto-detects IP/NIC)
- `/etc/systemd/system/libvirtd.service.d/override.conf` — persistent-libvirtd fix
- NetworkManager `Eagle6` DNS — pinned `1.1.1.1` (done 2026-09-20; `vm/fix-host-dns.sh` re-runnable)
- libvirt system objects: VM `casaos-vm`, `default` NAT net
- VM disk + data: `/home/je/NVMe4TB/RRRs_VM/{system.qcow2,RRRs_DATA/}` (`RRR_DISKDIR` overrides)
- Guest (`casaos-vm`): netplan from `machines/ailab/network-config` via seed.iso;
  static `192.168.122.50`; `/DATA` = virtiofs `rrrs-data`
- Autostart: `disable` (user preference — run `bash vm/vm-power.sh start` after each
  host boot). Enable with `sg libvirt -c "virsh autostart casaos-vm"` if wanted.
- Known quirk: a dormant qemu process (≈10 MB RSS, binds nothing) can linger after
  host suspend/resume. Harmless; kill it only if `virsh start` ever refuses.
