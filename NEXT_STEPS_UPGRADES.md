# RRRs — Next Steps & Upgrades

Everything optional, in order of value-for-effort. Current stack state:
NOTES-PROGRESS.md §8. Daily usage: HOWTO-USE.md.

## Do now (5 min)

1. ~~**Host DNS → 1.1.1.1 permanent**~~ — DONE (2026-08-16): script ran,
   resolv.conf = 1.1.1.1/8.8.8.8, poisoned domains resolve again.
   Reverse cmd inside vm/fix-host-dns.sh comments / NOTES §8j.
2. **Bookmark `http://P71.local:PORT`** instead of IPs — survives DHCP
   changes. Full table: `bash vm/current-urls.sh`. VPN on host is fine
   (full-tunnel carries the VM too); only a killswitch firewall would cut it.

## Books (Readarr) — MyAnonamouse [MAM], free

The one worth doing. Application-gated, not paid.

1. Register at `myanonamouse.net` → short application form (why you want in;
   genuine answer = usually approved in days).
2. Once in: account settings → generate **Passkey/RSS key**.
3. Prowlarr → Indexers → Add → "MyAnonamouse" → paste passkey → Test → Save.
4. Readarr: indexer auto-syncs via Prowlarr. Done — books + audiobooks.
   Rule: seed what you grab (community ratio, free leech events common).

## Music (Lidarr) — Rutracker, free

Private music trackers (Redacted/Orpheus) need interviews/invites — skip
unless you want that journey. The pragmatic option:

1. Register at `rutracker.org` (free; Russian UI — browser-translate it).
2. Prowlarr → Add Indexer → "Rutracker" → username + password → Test.
3. Music lands in Lidarr via sync. (FLAC selection is huge.)

## Usenet (Phase B) — ~$30–60/yr total

**What it unlocks**: private downloads (no IP logging by copyright trolls —
the main risk of torrents), full line speed with no seeding, 15+ years
retention (old/rare stuff that has 0 seeds on torrents).

1. **Provider** (the downloader's "ISP" for usenet):
   - Block account (best start): **NewsgroupDirect / FrugalUsenet /
     Usenet.Farm** deals — ~$20–50 for 200GB–1TB, never expires.
   - Or unlimited ~$5/mo (Newshosting/Frugal) if you'll pull >1TB/yr.
2. **SABnzbd**: http://P71.local:18080 → Settings → Servers → add
   host/port 563, SSL, your user/pass → green handshake. (Everything else
   is already wired: categories, dirs, arr clients.)
3. **Indexers** (search): start free — Prowlarr → add "Binsearch" +
   "NZBIndex" (no account). If weak, paid: **NZBGeek** ($2/mo or ~$30
   lifetime, opens registrations periodically), **Drunkenslug** (free tier).
4. Grab a test nzb via Prowlarr manual search → choose SABnzbd → lands in
   /DATA/Downloads/usenet/complete → arrs import it. Phase B done.

## Skipped on purpose

- **1337x**: Cloudflare level beats FlareSolverr 3.5.0 (FS only got EZTV
  through). Don't fight it — YTS/Limetorrents/LinuxTracker/EZTV cover it.
- **TPB**: definition no longer ships with Prowlarr 2.x.
