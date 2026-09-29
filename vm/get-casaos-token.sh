#!/bin/bash
# Fetch the CasaOS API token (JWT) via POST /v1/users/login -> vm/.casaos-token
# CasaOS v0.4.x has NO API-key field in the web UI: the Authorization token is
# issued by the login endpoint using the web-account credentials (REBUILD.md §6).
# Usage:
#   bash vm/get-casaos-token.sh                    # username defaults to 'je'
#   RRR_CASAOS_USER=alice bash vm/get-casaos-token.sh
# Password is prompted hidden; never appears in shell args or process lists.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 - <<'PY'
import getpass, json, os, sys, urllib.request
sys.path.insert(0, ".")  # script cd's to vm/ first
from _rrrhost import rrr_host
host = rrr_host()  # RRR_HOST env > machines/current/machine.env > autodetect
user = os.environ.get("RRR_CASAOS_USER", "je")
pw = getpass.getpass(f"CasaOS password for '{user}' @ {host}: ")
body = json.dumps({"username": user, "password": pw}).encode()
try:
    r = urllib.request.urlopen(urllib.request.Request(
        f"http://{host}:18000/v1/users/login", data=body,
        headers={"Content-Type": "application/json"}), timeout=15)
except urllib.error.HTTPError as e:
    raise SystemExit(f"login failed: HTTP {e.code} — wrong username/password?")
resp = json.load(r)
d = resp.get("data") or {}
tok = (d.get("token") or {}).get("access_token") or d.get("access_token")
if not tok:
    raise SystemExit(f"login failed: unexpected response: {str(resp)[:200]}")
fd = os.open(".casaos-token", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, tok.encode()); os.close(fd)
print("token saved to vm/.casaos-token")
PY
