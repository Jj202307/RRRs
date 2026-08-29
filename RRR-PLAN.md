# RRR (*arr) Stack on CasaOS — Implementation Plan

Handoff document from research session 2026-08-15. Read top to bottom in a fresh session, then execute Phase 0 → Phase A. Nothing has been installed yet.

## 1. Goal

Minimal self-hosted system on CasaOS to search and download (originally: from usenet; revised: free-first, usenet-ready) using the *arr tool suite: movies, TV, books/comics, music, plus ad-hoc manual grabs.

## 2. Decisions locked in (session 1)

- IN: Prowlarr, Radarr, Sonarr, Readarr, Lidarr. Downloader: SABnzbd (usenet) + qBittorrent (torrents, the free path).
- OUT: Jellyfin/Plex (no media server wanted), NZBHydra2 (superseded by Prowlarr), NZBGet (legacy).
- DEFERRED: Overseerr/Jellyseerr. Note: they are request frontends for a media server household; with no Jellyfin/Plex they add ~nothing. Recommendation: skip.
- OPTIONAL LATER: Bazarr (subtitle companion to Radarr/Sonarr), Whisparr (adult content variant of Sonarr).

## 3. Usenet reality check — is a paid provider required?

**Binary usenet without a paid provider: not possible.** Free public NNTP servers (Eternal September, AioE, etc.) carry text discussion groups only — no `alt.binaries.*`, which is where all media lives. Carrying binaries requires petabytes of storage, which is exactly what providers sell.

| | Usenet (paid provider) | Torrents (free) |
|---|---|---|
| Cost | Provider ~$3–5/mo (or prepaid block accounts); premium indexers optional | $0; public indexers need no account |
| Speed | Saturates your line, no upload | Depends on seeds |
| Privacy | SSL to provider, no uploading/seeding | You upload (seed); visible to peers/ISP |
| Old/rare content | Deep retention (paid providers keep 10+ years) | Weak for old/rare |
| Availability | NZB goes stale if past provider retention | While seeds exist |

**Strategy chosen: hybrid.**
- Phase A (now, $0): full *arr suite on CasaOS + qBittorrent + public torrent indexers in Prowlarr. Fully functional today.
- SABnzbd also installed now (free software), left without a server config — idle.
- Phase B (whenever a provider is bought): type server credentials into SABnzbd, add usenet indexers to Prowlarr. ~5 minutes, no reinstall.

## 4. Architecture

```
                    ┌─ Radarr  (movies)      :7878
Prowlarr :9696 ──── ├─ Sonarr  (TV)          :8989
(indexer hub +      ├─ Readarr (books)       :8787
 manual search)     └─ Lidarr  (music)       :8686
        │
        ├──► SABnzbd :8080        (usenet; idle until Phase B)
        └──► qBittorrent :8085    (torrents; active in Phase A)

/DATA/Media/{movies,tv,books,music}   ← libraries (hardlinks/moves land here)
/DATA/Downloads/usenet/{complete,incomplete}
/DATA/Downloads/torrents
```

## 5. Implementation steps

### Phase 0 — Preflight (on the CasaOS box)

1. Determine access mode: if this machine is the CasaOS host, shell + docker CLI are available; otherwise everything below is done via CasaOS web UI (browser).
2. Verify: `docker ps` works, `casaos -v` (optional), `/DATA` exists and is on the big disk.
3. Check UID: `id` → note PUID/PGID (CasaOS default is 1000/1000; every compose below assumes it).
4. Create directories via CasaOS Files UI (or `mkdir -p`):
   `/DATA/Media/{movies,tv,books,music}` and `/DATA/Downloads/{usenet/{complete,incomplete},torrents}`.

### Phase A — Free stack (torrents)

Order matters: downloader → Prowlarr → arrs → wiring.

1. **Prowlarr, Radarr, Sonarr, Readarr, Lidarr**: install from the official CasaOS App Store (verified present — see §8.1).
2. **qBittorrent**: check the official store first (presence NOT verified in session 1). If absent: CasaOS UI → App Store → custom install, paste compose from §6.2. Note: newer qBittorrent prints a temporary WebUI password in container logs on first start — retrieve with `docker logs qbittorrent`.
3. **SABnzbd** (install now, use later): not in official store (verified absent). Custom install with compose from §6.1.
4. **Prowlarr config**:
   - Add indexers: public torrent indexers requiring no account (e.g. 1337x, EZTV, ThePirateBay mirror set — availability varies; whatever loads and passes "Test"). Also add the account-free usenet indexers Binsearch and NZBIndex now — they query fine without a provider and will be ready for Phase B.
   - Settings → Download Clients → add SABnzbd (localhost:8080) and qBittorrent (localhost:8085) with their credentials. Enables manual grab → push.
   - Settings → Apps → add each arr: URL + that arr's API key (arr UI → Settings → General → API Key). Indexers then auto-sync to all arrs.
5. **Each arr**:
   - Settings → Download Clients → qBittorrent (and SABnzbd for Phase B readiness).
   - Root folders: Radarr→`/DATA/Media/movies`, Sonarr→`/DATA/Media/tv`, Readarr→`/DATA/Media/books`, Lidarr→`/DATA/Media/music`.
   - Sanity: leave quality profiles at defaults initially.
6. **Test procedure (Phase A exit criteria)**:
   - All containers `docker ps` healthy; each web UI reachable on its port.
   - Prowlarr: each indexer passes Test; manual search returns results.
   - Prowlarr manual grab of a legal test torrent (e.g. Ubuntu/Debian ISO or Big Buck Bunny) → qBittorrent downloads it → file appears under `/DATA/Downloads/torrents`.
   - Radarr: add a public-domain movie (Big Buck Bunny on TMDB) → auto-search grabs it → lands in `/DATA/Media/movies`.

### Phase B — Enable usenet (when a provider is acquired)

1. Buy provider (examples: Frugalusenet, Newshosting, Eweka; block accounts = prepaid GB, no expiry — good for light use). Record: host, port 563 (SSL), username, password, connection count.
2. SABnzbd → Settings → Servers → add. Green handshake = live. Keep PAR2 repair defaults.
3. Prowlarr → add premium usenet indexers if desired (Drunkenslug, NZBGeek, omgwtfnzbs; free tiers exist on some) — Binsearch/NZBIndex already added in Phase A.
4. Each arr: ensure SABnzbd is an enabled download client and "Usenet" priority vs torrents to taste (common: usenet preferred, torrent fallback).
5. Test: Prowlarr manual NZB grab → SABnzbd queue → completed file in `/DATA/Downloads/usenet/complete`, repaired and extracted.

### Phase C — Optional extras (all deferred, decide never or later)

- Bazarr (subtitles; needs only Radarr/Sonarr) — port 6767.
- Overseerr :5055 / Jellyseerr :5056 — only meaningful with a media server; currently OUT.
- Whisparr — only if its content category is wanted.

## 6. Compose snippets (CasaOS custom install)

### 6.1 SABnzbd

```yaml
services:
  sabnzbd:
    image: linuxserver/sabnzbd:latest
    container_name: sabnzbd
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - /DATA/Config/sabnzbd:/config
      - /DATA/Downloads/usenet/complete:/downloads/complete
      - /DATA/Downloads/usenet/incomplete:/downloads/incomplete
    ports:
      - 8080:8080
    restart: unless-stopped
```

### 6.2 qBittorrent (fallback if not in store)

```yaml
services:
  qbittorrent:
    image: linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
    volumes:
      - /DATA/Config/qbittorrent:/config
      - /DATA/Downloads/torrents:/downloads
    ports:
      - 8085:8080
      - 6881:6881
      - 6881:6881/udp
    restart: unless-stopped
```

Port collision warning: qBittorrent's internal WebUI is 8080 — same as SABnzbd. Never map both to host 8080. Host ports: SABnzbd 8080, qBittorrent 8085.

## 7. Fresh-session kick-off prompt

> Read RRR-PLAN.md in this folder. Execute Phase 0 preflight, then Phase A. Stop and report after each numbered step. Use the compose snippets in §6 as-is unless preflight says otherwise.

## 8. Session knowledge appendix

### 8.1 Verified facts (2026-08-15, via GitHub API on IceWhaleTech/CasaOS-AppStore)

- Present in official store: Prowlarr, Radarr, Sonarr, Readarr, Lidarr (each `Apps/<Name>/docker-compose.yml`).
- Absent from official store: SABnzbd, NZBGet, NZBHydra2 (404 on those paths).
- Unverified: qBittorrent presence in official store.

### 8.2 Port map

| App | Port |
|---|---|
| Prowlarr | 9696 |
| Radarr | 7878 |
| Sonarr | 8989 |
| Readarr | 8787 |
| Lidarr | 8686 |
| SABnzbd | 8080 |
| qBittorrent (host) | 8085 |
| Bazarr | 6767 |
| Overseerr / Jellyseerr | 5055 / 5056 |

### 8.3 *arr cheat sheet (one-liners)

- Radarr: wishlist-automated movie downloads.
- Sonarr: same for TV series/seasons/episodes.
- Lidarr: same for music artists/albums.
- Readarr: same for ebooks/audiobooks/comics. (Least-maintained of the suite; expect quirks.)
- Prowlarr: central indexer manager + manual search; syncs indexers into every other arr.
- Bazarr: subtitle fetcher for Radarr/Sonarr libraries.
- Whisparr: adult-content Sonarr variant.
- SABnzbd: usenet download client (fetch, PAR2-repair, extract).
- qBittorrent: torrent download client.

### 8.4 Web-fetch tooling notes (why searches failed in session 1)

- jmunch-fetch itself works (Wikipedia, GitHub API fetched fine).
- Every general search engine failed, two distinct causes:
  1. robots.txt `Disallow` for autonomous crawlers: Bing, Mojeek, Brave, Ecosia, Startpage, Reddit, Marginalia. The fetch tool honors robots.txt.
  2. Bot challenges: DuckDuckGo (HTML + lite endpoints) served CAPTCHAs; Searx.be served a browser-verification page.
- Practical rule for future sessions: skip search engines; fetch known URLs and APIs (GitHub API, project docs) directly.
- Whether this tightening is "new" could not be verified from inside the session.

### 8.5 Environment

- Plan authored on: linux, dir `/home/je/Downloads/Projects/RRRs` (was empty besides this file). Not a git repo.
- Unknowns for fresh session to resolve: is this machine the CasaOS host or a client; actual PUID/PGID; whether store qBittorrent exists.
