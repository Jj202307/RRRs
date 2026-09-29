# TEMPLATE — deriving values for a NEW machine (SET C, D, ...)

Copy this dir (`vm/select-machine.sh new <name>`), fill `machine.env`, activate
(`vm/select-machine.sh <name>`). Every value left empty autodetects at runtime.

## Derivation cheatsheet

| machine.env key | How to find it | Notes |
|---|---|---|
| `M_OS` | `cat /etc/os-release` | Only matters for choosing the host-prep script |
| `M_HOST_PREP` | Ubuntu/Debian → `vm/setup_host_Ubuntu.sh`; openSUSE → `vm/setup_host_OpenSuseOS.sh`; else adapt one | Run with sudo on a fresh host |
| `M_LAN_IF_DEFAULT` | `ip route show default` → `dev <X>` | The default-route NIC (not the bridge/veth noise) |
| `M_NM_CONN` | `nmcli -t -f NAME,DEVICE,STATE con show \| grep ':<X>:activated'` | Only for `fix-host-dns.sh`; leave empty on non-NM hosts and edit that script |
| `M_LAN_IP_DEFAULT` | `ip -4 addr show <X> \| grep -oP 'inet \K[\d.]+'` | Snapshot; autodetect handles DHCP drift |
| `M_URL_HOST` / `M_MDNS_OK` | `ping -c1 -W1 $(hostname).local` — resolves to the LAN IP? `1`/use it. Resolves to docker/bridge junk or nothing? `0`/use the IP | Hosts running Docker/K8s bridges almost always need `0` |
| `M_GUEST_MTU` | `ping -M do -s 1472 1.1.1.1`; decrease until it passes; largest passing size + 28 = path MTU | WiFi hotspots often 1280 (like ailab). Wired LANs usually clean 1500 → leave empty |

## Guest DNS ordering decision (network-config variant)

- Host DNS pinned to `1.1.1.1` (fix-host-dns.sh) AND you want VPN-pushed DNS to reach
  the guest → put `192.168.122.1` (host dnsmasq) FIRST (copy `machines/ailab/`).
- Host DNS untrusted/poisoned by ISP → put `1.1.1.1, 8.8.8.8` FIRST (copy `machines/P71/`).

## Preflight on the new machine

```bash
ss -tlnp | grep -E ':(10022|18000|19696|17878|18989|18787|18686|18080|18085|16881) '   # must be empty
ls /dev/kvm && ls /usr/libexec/virtiofsd   # KVM + virtiofs daemon present (host prep installs them)
```

Then follow REBUILD.md top-to-bottom, starting with `bash vm/select-machine.sh <name>`.
Append your SSH public key to `vm/user-data` (`ssh_authorized_keys:`) so `check-vm.sh`
and `collect-keys.sh` get key auth on the fresh VM.
