#!/usr/bin/env python3
"""Shared host-IP resolver for the RRRs python entry points.

Resolution order: RRR_HOST env > machines/current/machine.env M_LAN_IP_DEFAULT >
autodetect (default-route src IP). Raises a helpful error if nothing works.
"""
import os, re, subprocess

def rrr_host() -> str:
    ip = os.environ.get("RRR_HOST")
    if ip:
        return ip
    here = os.path.dirname(os.path.abspath(__file__))
    envf = os.path.join(here, "..", "machines", "current", "machine.env")
    try:
        with open(envf) as f:
            for ln in f:
                m = re.match(r'\s*M_LAN_IP_DEFAULT\s*=\s*"([^"]+)"', ln)
                if m:
                    return m.group(1)
    except OSError:
        pass
    try:
        out = subprocess.check_output(["ip", "route", "show", "default"], text=True)
        m = re.search(r"\bsrc (\d+\.\d+\.\d+\.\d+)\b", out)
        if m:
            return m.group(1)
    except Exception:
        pass
    raise SystemExit("ERROR: cannot determine the host IP — export RRR_HOST=<lan-ip> or run vm/select-machine.sh <set>")
