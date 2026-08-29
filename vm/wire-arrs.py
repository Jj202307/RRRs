#!/usr/bin/env python3
"""Wire up Prowlarr + *arrs: download clients, indexers, applications, root folders, remote path mappings.
Run from host. All API calls go through host port forwards.
Stages can be run individually: --stage prowlarr-clients|indexers|applications|arr-folders|arr-clients|arr-rpm|sync|verify|test
"""
import argparse, json, sys, urllib.request, urllib.error

import os
HOST = os.environ.get("RRR_HOST", "192.168.1.81")
BRIDGE = "172.17.0.1"  # guest docker0 gateway — how containers reach each other's published ports
APPS = {
    "prowlarr": (f"http://{HOST}:19696", "4162dc4c35b248b6acbc86f145b34d1f", "v1"),
    "radarr":   (f"http://{HOST}:17878", "edc03b29e50a4a27bd008d5bee059b02", "v3"),
    "sonarr":   (f"http://{HOST}:18989", "3d175c22d0384e0d845093a4396b7a34", "v3"),
    "readarr":  (f"http://{HOST}:18787", "959bbc492cd448889bae56582a4618bf", "v1"),
    "lidarr":   (f"http://{HOST}:18686", "988427244e4c431f86cce4d45b65249f", "v1"),
}
GUEST_PORT = {"prowlarr": 9696, "radarr": 7878, "sonarr": 8989, "readarr": 8787, "lidarr": 8686, "qbittorrent": 8085, "sabnzbd": 8080}
QB_USER, QB_PASS = "admin", "i7oCkokxEhAtHT8A"
SAB_APIKEY = "350f7db486cf40e9a2693f81a94caa4e"
ARR_CATEGORY = {"radarr": "radarr", "sonarr": "tv-sonarr", "readarr": "readarr", "lidarr": "lidarr"}
ROOT_FOLDER = {"radarr": "/movies", "sonarr": "/tv", "readarr": "/books", "lidarr": "/music"}
INDEXERS = ["1337x", "EZTV"]

def req(app, method, path, body=None):
    base, key, ver = APPS[app]
    url = f"{base}/api/{ver}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method,
                               headers={"X-Api-Key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=40) as resp:
            txt = resp.read().decode()
            return json.loads(txt) if txt.strip().startswith(("[", "{")) else txt
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {url} -> {e.code}: {e.read().decode()[:400]}")

def get_schema(app, res, implementation):
    for s in req(app, "GET", f"{res}/schema"):
        if s.get("implementation") == implementation:
            return s
    raise RuntimeError(f"schema {implementation} not found in {app} {res}")

def fill(sch, values):
    for f in sch.get("fields", []):
        if f["name"] in values:
            f["value"] = values[f["name"]]
    return sch

def upsert(app, res, body, name=None):
    name = name or body.get("name")
    for x in req(app, "GET", res):
        if x.get("name") == name:
            body["id"] = x["id"]
            req(app, "PUT", res, body)
            return f"updated {name} (id {x['id']})"
    out = req(app, "POST", res, body)
    return f"created {name} (id {out.get('id')})"

def stage_prowlarr_clients():
    qb = fill(get_schema("prowlarr", "downloadclient", "QBittorrent"), {
        "host": BRIDGE, "port": GUEST_PORT["qbittorrent"], "useSsl": False,
        "username": QB_USER, "password": QB_PASS, "category": "prowlarr"})
    qb.update({"enable": True, "name": "qBittorrent", "priority": 25, "tags": []})
    print("prowlarr dlclient:", upsert("prowlarr", "downloadclient", qb))
    sab = fill(get_schema("prowlarr", "downloadclient", "Sabnzbd"), {
        "host": BRIDGE, "port": GUEST_PORT["sabnzbd"], "useSsl": False,
        "apiKey": SAB_APIKEY, "category": "prowlarr"})
    sab.update({"enable": True, "name": "SABnzbd", "priority": 25, "tags": []})
    print("prowlarr dlclient:", upsert("prowlarr", "downloadclient", sab))

def stage_indexers():
    for impl in INDEXERS:
        sch = None
        for s in req("prowlarr", "GET", "indexer/schema"):
            if impl.lower() == s.get("name", "").lower():
                sch = s; break
        if not sch:
            print(f"indexer {impl}: no definition, skipped"); continue
        sch.update({"enable": True, "name": impl, "appProfileId": 1, "priority": 25, "tags": [1]})
        try:
            print(f"indexer {impl}:", upsert("prowlarr", "indexer", sch))
        except RuntimeError as e:
            print(f"indexer {impl}: FAILED — {str(e)[:160]}")

def stage_applications():
    for app in ("radarr", "sonarr", "readarr", "lidarr"):
        sch = fill(get_schema("prowlarr", "applications", app.capitalize()), {
            "baseUrl": f"http://{BRIDGE}:{GUEST_PORT[app]}",
            "apiKey": APPS[app][1],
            "prowlarrUrl": f"http://{BRIDGE}:{GUEST_PORT['prowlarr']}"})
        sch.update({"enable": True, "name": app.capitalize(), "syncLevel": "fullSync", "tags": []})
        print(f"application {app}:", upsert("prowlarr", "applications", sch))

def stage_arr_folders():
    for app, path in ROOT_FOLDER.items():
        have = req(app, "GET", "rootfolder")
        if any(r["path"].rstrip("/") == path for r in have):
            print(f"{app}: rootfolder {path} exists"); continue
        body = {"path": path}
        if app in ("readarr", "lidarr"):
            body["name"] = path.strip("/").capitalize()
            try:  # lidarr/readarr want default profile ids; pick the first of each
                body["defaultMetadataProfileId"] = req(app, "GET", "metadataprofile")[0]["id"]
                body["defaultQualityProfileId"] = req(app, "GET", "qualityprofile")[0]["id"]
            except Exception as e:
                print(f"{app}: profile lookup failed ({str(e)[:80]}), trying without")
        try:
            req(app, "POST", "rootfolder", body)
            print(f"{app}: rootfolder {path} created")
        except RuntimeError as e:
            print(f"{app}: rootfolder FAILED {e}")

def stage_arr_clients():
    for app, cat in ARR_CATEGORY.items():
        qb = fill(get_schema(app, "downloadclient", "QBittorrent"), {
            "host": BRIDGE, "port": GUEST_PORT["qbittorrent"], "useSsl": False,
            "username": QB_USER, "password": QB_PASS, "category": cat, "musicCategory": cat})
        qb.update({"enable": True, "name": "qBittorrent", "priority": 25, "tags": []})
        print(f"{app} dlclient:", upsert(app, "downloadclient", qb))
        sab = fill(get_schema(app, "downloadclient", "Sabnzbd"), {
            "host": BRIDGE, "port": GUEST_PORT["sabnzbd"], "useSsl": False,
            "apiKey": SAB_APIKEY, "category": cat, "musicCategory": cat})
        sab.update({"enable": True, "name": "SABnzbd", "priority": 25, "tags": []})
        print(f"{app} dlclient:", upsert(app, "downloadclient", sab))

def stage_arr_rpm():
    body = {"host": BRIDGE, "remotePath": "/DATA/Downloads/", "localPath": "/downloads/"}
    for app in ("radarr", "sonarr", "readarr", "lidarr"):
        have = req(app, "GET", "remotepathmapping")
        if any(m["remotePath"] == body["remotePath"] for m in have):
            print(f"{app}: rpm exists"); continue
        req(app, "POST", "remotepathmapping", body)
        print(f"{app}: rpm {BRIDGE} {body['remotePath']} -> {body['localPath']} created")

def stage_sync():
    req("prowlarr", "POST", "command", {"name": "ApplicationIndexerSync"})
    print("prowlarr AppIndexerSync command issued")

def stage_verify():
    print("== prowlarr indexers:")
    for i in req("prowlarr", "GET", "indexer"):
        print(f"  {i['name']:15} priv={i.get('privacy')} enable={i['enable']}")
    print("== prowlarr applications:")
    for a in req("prowlarr", "GET", "applications"):
        print(f"  {a['name']:10} enable={a['enable']}")
    for app in ("radarr", "sonarr", "readarr", "lidarr"):
        idx = req(app, "GET", "indexer")
        rf = req(app, "GET", "rootfolder")
        dc = req(app, "GET", "downloadclient")
        rpm = req(app, "GET", "remotepathmapping")
        print(f"== {app}: {len(idx)} indexers, roots={[r['path'] for r in rf]}, clients={[d['name'] for d in dc]}, rpms={len(rpm)}")

def stage_test():
    for dc in req("prowlarr", "GET", "downloadclient"):
        try:
            req("prowlarr", "POST", "downloadclient/action/test", dc)
            print(f"test dlclient {dc['name']}: OK")
        except RuntimeError as e:
            print(f"test dlclient {dc['name']}: FAIL {str(e)[:150]}")
    for i in req("prowlarr", "GET", "indexer"):
        try:
            req("prowlarr", "POST", "indexer/action/test", i)
            print(f"test indexer {i['name']}: OK")
        except RuntimeError as e:
            print(f"test indexer {i['name']}: FAIL — {str(e)[:200]} (kept)")

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--stage", required=True,
                   choices=["prowlarr-clients", "indexers", "applications", "arr-folders",
                            "arr-clients", "arr-rpm", "sync", "verify", "test"])
    a = p.parse_args()
    {"prowlarr-clients": stage_prowlarr_clients, "indexers": stage_indexers,
     "applications": stage_applications, "arr-folders": stage_arr_folders,
     "arr-clients": stage_arr_clients, "arr-rpm": stage_arr_rpm,
     "sync": stage_sync, "verify": stage_verify, "test": stage_test}[a.stage]()
