#!/usr/bin/env python3
"""Install the 7 RRRs apps into CasaOS via its v2 AppManagement API.

- Reads store compose templates from vm/appcomposes/*.json
  (fetched earlier: GET /v2/app_management/apps/{id}/compose).
- Interpolates $TZ/$PUID/$PGID/$AppID, rewrites published ports to our guest
  port map, adds qBittorrent torrent port 6881 tcp+udp.
- POSTs each as application/yaml (JSON is valid YAML) to
  POST /v2/app_management/compose[?dry_run=true].

Run on the host: python3 vm/install-apps.py [--dry-run-only] [--app NAME]
"""
import json, sys, os, urllib.request

BASE = f"http://{__import__('os').environ.get('RRR_HOST', '192.168.1.81')}:18000/v2/app_management"
HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN = open(os.path.join(HERE, ".casaos-token")).read().strip()

TZ, PUID, PGID = "Europe/Athens", "1000", "1000"
# app -> guest published webui port (host NAT maps host->guest)
WEBUI = {"prowlarr": "9696", "radarr": "7878", "sonarr": "8989",
         "readarr": "8787", "lidarr": "8686", "qbittorrent": "8085",
         "sabnzbd": "8080"}
ORDER = ["qbittorrent", "sabnzbd", "prowlarr", "radarr", "sonarr",
         "readarr", "lidarr"]


def interp(o):
    if isinstance(o, str):
        return (o.replace("$TZ", TZ).replace("$PUID", PUID)
                 .replace("$PGID", PGID))
    if isinstance(o, list):
        return [interp(x) for x in o]
    if isinstance(o, dict):
        return {k: interp(v) for k, v in o.items()}
    return o


def post_yaml(body: str, dry: bool):
    url = BASE + "/compose" + ("?dry_run=true" if dry else "")
    req = urllib.request.Request(url, data=body.encode(),
                                 headers={"Content-Type": "application/yaml",
                                          "Authorization": TOKEN},
                                 method="POST")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read().decode()[:400]
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def main():
    args = sys.argv[1:]
    dry_only = "--dry-run-only" in args
    only = None
    if "--app" in args:
        only = args[args.index("--app") + 1]
    apps = [only] if only else ORDER
    for app in apps:
        tpl = json.load(open(os.path.join(HERE, "appcomposes", f"{app}.json")))
        c = tpl["data"]["compose"]
        c = interp(c)
        # $AppID == app name
        c = json.loads(json.dumps(c).replace("$AppID", app))
        svc = c["services"][app]
        # first port = webui -> publish on our guest port
        if svc.get("ports"):
            svc["ports"][0]["published"] = WEBUI[app]
        if app == "qbittorrent":
            svc["ports"] += [{"target": 6881, "published": "6881", "protocol": "tcp"},
                             {"target": 6881, "published": "6881", "protocol": "udp"}]
        # keep x-casaos port_map consistent if present
        try:
            c["x-casaos"]["port_map"]["webui_port"] = WEBUI[app]
        except (KeyError, TypeError):
            pass
        body = json.dumps(c)
        st, msg = post_yaml(body, dry=True)
        print(f"[{app}] dry_run -> {st} {msg}")
        if st == 200 and not dry_only:
            st2, msg2 = post_yaml(body, dry=False)
            print(f"[{app}] INSTALL -> {st2} {msg2}")


if __name__ == "__main__":
    main()
