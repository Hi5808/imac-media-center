# The download stack

`Prowlarr :9696` finds releases → `Sonarr :8989` (TV) and `Radarr :7878` (films) decide
and rename → `Transmission :9091` downloads → the `*arr` app imports into `/srv/media`
and tells Kodi to refresh.

Downloads and media sit on the same filesystem on purpose, so imports **hardlink** instead
of copying. Shared group `media`, directories `2775` setgid.

## Codec filtering is mandatory here

This GPU cannot decode HEVC, VP9 or AV1 **at all**, and software-decoding 1080p HEVC on a
Core 2 Duo is hopeless. So unplayable releases have to be rejected before they are grabbed.

- **Sonarr** — release profile *"No HEVC or 4K"*. Plain terms alone are **not enough**;
  see the warning below. Use:

  ```
  x265  HEVC  h265  2160p  4K  XviD  DivX  AV1  VP9
  /[xh][.\s_-]?265/i   /\b2160\b/i   /\bav1\b/i   /\bvp9\b/i
  ```

- **Radarr** has no release profiles, so instead: custom format
  *"Unplayable here (x265/HEVC/4K)"* scored **-10000** in every profile you use.
  Its conditions are regexes already, and `(x265|[hx]\.?265|HEVC)` is the important one.
- Use quality profile **6 (HD - 720p/1080p)** for anything added by hand. The default
  "Any" (id 1) permits SD.

> **Plain substring terms miss dotted codec names.** A release called
> `Chief.of.War.S01E08-09.1080p.ATVP.WEB-DL.DDP5.1.Atmos.H.265-G6` contains neither
> `h265` nor `x265` — the dot breaks both — so a term list of `x265, HEVC, h265` lets
> it straight through, and it is completely unplayable on this GPU. This was found live,
> on a release advertising 28 seeders. Scene names also use `x.265`, `H 265` and
> `h_265`, hence the `[.\s_-]?` in the regex above. Sonarr treats a term wrapped in
> `/…/` as a regex; `/…/i` makes it case-insensitive.

Sanity-check your filtering against a real search before trusting it:

```sh
curl -s -H "X-Api-Key: $SONARR_KEY" \
  "http://127.0.0.1:8989/api/v3/release?episodeId=N" |
  python3 -c 'import sys,json
for x in json.load(sys.stdin):
    t=x["title"].lower().replace(".","").replace(" ","")
    if any(k in t for k in ("x265","h265","hevc","2160")) and not x["rejected"]:
        print("LEAK:",x["title"])'
```

Anything printed is a release your profile would have grabbed and could not play.

The panel is 1680x1050, so 1080p is downscaled on playback anyway — 720p x264 looks
near-identical here and downloads far more reliably.

## FlareSolverr must live on another machine

Some indexers (1337x, EZTV) sit behind CloudFlare and fail Prowlarr's connectivity test
without FlareSolverr. **FlareSolverr cannot run on this iMac** — it drives a headless
Chrome, and this CPU has no SSE4.2.

Run it on any other machine on the LAN, bound to `0.0.0.0:8191`, then in Prowlarr:

1. Create a tag, e.g. `flaresolverr`.
2. Add **Settings → Indexer Proxies → FlareSolverr**, host `http://<other-host>:8191/`,
   and give it that tag.
3. Add the 1337x and EZTV indexers **carrying the same tag**.

Verify the solver itself independently of Prowlarr:

```sh
curl -s -X POST -H 'Content-Type: application/json' \
  -d '{"cmd":"request.get","url":"https://1337x.to/","maxTimeout":100000}' \
  http://<other-host>:8191/v1
```

`"message":"Challenge solved!"` means it works. On this setup, adding these two indexers
took a search from 44 results to 82, and they are the ones carrying per-episode 1080p
H.264 releases.

### Adding indexers over the API

Prowlarr rejects a schema definition POSTed verbatim:

```
GreaterThanValidator / App Profile Id
```

You must inject `appProfileId` (copy it from an existing indexer), plus `tags` and
`enable`. Also, `POST /api/v1/indexer/test?id=N` returns **415** unless you send a JSON
body — running an actual search is the more useful check.

## Working with releases without grabbing them

This is the safe way to see what is available:

```sh
curl -s -H "X-Api-Key: $SONARR_KEY" \
  "http://127.0.0.1:8989/api/v3/release?seriesId=N&seasonNumber=M"
```

It lists every candidate with `rejected` and `rejections` explaining each refusal, and
**grabs nothing**. To then grab one deliberately, POST just its `guid` and `indexerId` to
`/api/v3/release`.

## Lessons about public indexers

- **Reported seeder counts lie, badly.** One E09 release was listed at **1112 seeders** on
  one indexer and 29 on another, while its own trackers reported **0 seeders and 3
  leechers**. Treat the indexer's number as a rumour and the tracker's as evidence:
  `transmission-remote <host> -n <auth> -t N -it` prints what the trackers actually said.
- **A stuck magnet blocks healthy downloads.** Transmission counts torrents still fetching
  metadata against its active-download limit, so three dead magnets held five slots and
  kept two perfectly healthy 70-seeder torrents in `Queued` indefinitely. Removing the
  dead ones started the good ones within seconds. If something is queued and nothing is
  progressing, look for `Idle` + `Have: None` entries and clear them out first.
- **Season packs are the trap.** Of three tried on one show, all three died at zero peers —
  and one of them reached 3% / 189MB *before* losing every peer, so a pack starting is no
  evidence it will finish. Per-episode releases from EZTV worked where every pack failed.
- **Diagnosing a dead magnet:** `transmission-remote <host> -n <auth> -t N -i`. A state of
  `Idle` with `Have: None` means metadata never arrived, which is a different failure from
  having 0% of known files. Treat "no metadata and 0 peers after ~5 minutes" as dead.
- **Removing a dead grab**, so it is not immediately re-grabbed:

  ```sh
  curl -X DELETE -H "X-Api-Key: $KEY" \
    "http://127.0.0.1:8989/api/v3/queue/$ID?removeFromClient=true&blocklist=true&skipRedownload=true"
  ```

  When several queue rows share one torrent, deleting the first 404s the rest. That is
  expected — loop over all the ids.

## The stack acts on its own

`RssSync` runs **every 15 minutes** and auto-grabs new releases of any *monitored* episode.
Adding a series sets `monitored=all`, so it can produce a dozen queue entries within
seconds. If you want it quiet, turn monitoring off deliberately.

## Other things that bite

- **Transmission AppArmor.** The profile has `include if exists <local/transmission>`, so
  the `/srv/downloads` and `/srv/media` rules must go in
  `/etc/apparmor.d/local/transmission` — see `config/apparmor-local-transmission.example`.
  Without it you get permission-denied *and* a segfault.
- **Transmission runs only 5 active downloads**; the rest show `Queued` and start as others
  finish. This build's `transmission-remote` has no queue flags at all, so changing it means
  editing `settings.json` and restarting the daemon.
- **Transmission rewrites `settings.json` on exit.** Stop the service before editing it.
- Use `127.0.0.1`, not `localhost`, in the `*arr` cross-app settings.
- Kodi notifications: on both `*arr` apps add connection type `Xbmc` pointing at
  `127.0.0.1:8080`, so an import refreshes the library.
