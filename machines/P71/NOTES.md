# SET A — P71 (original host, openSUSE Leap 16)

As-built 2026-09-13..20. Retired as primary host 2026-09-20 (stack moved to `ailab`).
Original as-built state is preserved in git `1cc753e` — note it predates the virtiofs
`/DATA` redesign (P71 used a 200G `data.qcow2` disk). A REBUILD on P71 today uses the
shared current design (virtiofs share, see `vm/build-vm.sh`) with THIS set's values.

## What's different from other sets

| Value | P71 value |
|---|---|
| OS / libvirt | openSUSE Leap 16, MODULAR daemons (`virtqemud`, `virtnetworkd`, …) |
| Host prep | `sudo bash vm/setup_host_OpenSuseOS.sh` (zypper) + `sudo bash vm/finish-host-setup.sh` |
| Uplink | wired `enp0s31f6`, NM connection "Wired connection 1", clean 1500 path MTU |
| Guest DNS order | public resolvers FIRST (`1.1.1.1`, `8.8.8.8`) — ISP poisoned the host-chain here (NOTES §8e) |
| URL host | `P71.local` (mDNS valid — no Docker bridges on that host) |
| As-built LAN IP | `192.168.1.81` (DHCP; scripts autodetect the current IP anyway) |

## Functional locations on this machine (host = P71)

- `/etc/libvirt/hooks/qemu` — port-forward + MSS-clamp hook (installed by
  `finish-host-setup.sh`; auto-detects host IP/NIC from the default route — nothing
  P71-specific inside it)
- NetworkManager connection DNS — `vm/fix-host-dns.sh` pins `1.1.1.1/8.8.8.8`
- libvirt system objects: VM `casaos-vm`, `default` NAT net (192.168.122.1/24)
- VM disk + data: `/home/je/NVMe4TB/RRRs_VM/{system.qcow2,RRRs_DATA/}` (default; override with `RRR_DISKDIR`)
- Guest (`casaos-vm`): netplan from `machines/P71/network-config` via seed.iso;
  static `192.168.122.50`; `/DATA` = virtiofs `rrrs-data`

## VPN on P71

Never live-verified (Surfshark is installed on ailab only). Expectation based on the
same policy-routing mechanism: host VPN full-tunnel carries the NATed VM traffic
automatically. Verify after installing: compare `curl -s https://api.ipify.org` on
host vs inside the VM (`ssh -p 10022 debian@<ip>`).
