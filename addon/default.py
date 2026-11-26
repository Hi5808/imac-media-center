# -*- coding: utf-8 -*-
"""Find Media - run Sonarr/Radarr from inside Kodi.

Search and add titles, see what is downloading, browse your shows, toggle
monitoring, and kick off searches - without opening a browser.
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

import xbmc
import xbmcaddon
import xbmcgui
import xbmcplugin

ADDON = xbmcaddon.Addon()
HANDLE = int(sys.argv[1])
BASE = sys.argv[0]
TIMEOUT = 45

ON = "[COLOR lime]ON[/COLOR]"
OFF = "[COLOR red]OFF[/COLOR]"


def notify(msg, ms=4000):
    xbmcgui.Dialog().notification("Find Media", msg, xbmcgui.NOTIFICATION_INFO, ms)


def cfg(key):
    return ADDON.getSetting(key).strip()


def api(service, path, payload=None, method=None):
    base = cfg("%s_url" % service).rstrip("/")
    key = cfg("%s_key" % service)
    if not base or not key:
        return False, "%s URL or API key not set (Add-on settings)" % service.title()
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(base + path, data=data,
                                 method=method or ("POST" if data else "GET"))
    req.add_header("X-Api-Key", key)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            body = resp.read().decode("utf-8")
            return True, (json.loads(body) if body.strip() else None)
    except urllib.error.HTTPError as exc:
        return False, "HTTP %s: %s" % (exc.code, exc.read().decode("utf-8", "replace")[:200])
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def fail(what, err):
    xbmcgui.Dialog().ok("Find Media", "%s failed:\n%s" % (what, err))


def url_for(**kwargs):
    return BASE + "?" + urllib.parse.urlencode(kwargs)


def art_of(item):
    out = {}
    for image in item.get("images") or []:
        link = image.get("remoteUrl") or image.get("url")
        if not link:
            continue
        if image.get("coverType") == "poster":
            out["poster"] = link
            out.setdefault("thumb", link)
        elif image.get("coverType") == "fanart":
            out["fanart"] = link
    return out


def add_item(label, plot=None, art=None, folder=True, **params):
    li = xbmcgui.ListItem(label=label)
    if art:
        li.setArt(art)
    if plot:
        li.getVideoInfoTag().setPlot(plot)
    xbmcplugin.addDirectoryItem(HANDLE, url_for(**params), li, isFolder=folder)


def end():
    xbmcplugin.addSortMethod(HANDLE, xbmcplugin.SORT_METHOD_NONE)
    xbmcplugin.endOfDirectory(HANDLE)


def confirm_download(what):
    """Searching starts real downloads, so always ask first."""
    return xbmcgui.Dialog().yesno(
        "Find Media",
        "Search indexers and download:\n[B]%s[/B]\n\nThis will use bandwidth and disk." % what,
        yeslabel="Search now", nolabel="Cancel")


# --------------------------------------------------------------------------- menus
def root():
    add_item("Search for a TV show", "Look up a series and add it to Sonarr",
             action="search", service="sonarr")
    add_item("Search for a movie", "Look up a film and add it to Radarr",
             action="search", service="radarr")
    add_item("My shows", "Monitoring on/off, search seasons or whole series",
             action="shows")
    add_item("My movies", "Monitoring on/off, search for a film again",
             action="movies")
    add_item("Downloading now", "What Sonarr and Radarr are fetching", action="queue")
    add_item("Wanted / missing TV", "Pick an episode to search for it", action="wanted")
    add_item("Refresh Kodi library", "Rescan /srv/media", action="rescan")
    end()


def search(service):
    kb = xbmc.Keyboard("", "Search %s" % ("TV shows" if service == "sonarr" else "movies"))
    kb.doModal()
    if not kb.isConfirmed() or not kb.getText().strip():
        end()
        return
    term = kb.getText().strip()
    kind = "series" if service == "sonarr" else "movie"
    ok, data = api(service, "/api/v3/%s/lookup?term=%s" % (kind, urllib.parse.quote(term)))
    if not ok:
        fail("Search", data)
        end()
        return
    if not data:
        notify("Nothing found for '%s'" % term)
        end()
        return
    for item in data[:40]:
        mark = "[COLOR lime]* [/COLOR]" if item.get("id") else ""
        ident = item.get("tvdbId") if service == "sonarr" else item.get("tmdbId")
        add_item("%s%s (%s)" % (mark, item.get("title", "?"), item.get("year") or "?"),
                 (item.get("overview") or "")[:600], art_of(item),
                 action="add", service=service, ident=ident or 0,
                 title=item.get("title", "?"))
    end()


def add(service, ident, title):
    kind = "series" if service == "sonarr" else "movie"
    idfield = "tvdbId" if service == "sonarr" else "tmdbId"
    ok, found = api(service, "/api/v3/%s/lookup?term=%s" % (kind, urllib.parse.quote(title)))
    if not ok or not found:
        fail("Lookup", found)
        end()
        return
    item = None
    for cand in found:
        if str(cand.get(idfield)) == str(ident):
            item = cand
            break
    item = item or found[0]
    if item.get("id"):
        notify("%s is already in your library" % item.get("title"))
        end()
        return
    if not confirm_download("%s (%s)" % (item.get("title"), item.get("year") or "?")):
        end()
        return
    body = {
        "title": item["title"], idfield: item[idfield], "titleSlug": item["titleSlug"],
        "qualityProfileId": int(cfg("%s_profile" % service) or 6),
        "rootFolderPath": cfg("%s_root" % service),
        "monitored": True, "images": item.get("images", []),
    }
    if service == "sonarr":
        body.update({"seasonFolder": True, "seriesType": "standard",
                     "seasons": item.get("seasons", []),
                     "addOptions": {"searchForMissingEpisodes": True, "monitor": "all"}})
    else:
        body.update({"year": item.get("year"), "minimumAvailability": "released",
                     "addOptions": {"searchForMovie": True}})
    ok, res = api(service, "/api/v3/%s" % kind, body)
    if ok:
        notify("Added %s - searching now" % item.get("title"), 5000)
    else:
        fail("Add", res)
    end()


def shows():
    ok, data = api("sonarr", "/api/v3/series")
    if not ok:
        fail("Series list", data)
        end()
        return
    if not data:
        add_item("No shows yet", "Use 'Search for a TV show' to add one", action="root")
    for s in sorted(data, key=lambda x: x.get("sortTitle") or x.get("title", "")):
        st = s.get("statistics", {})
        add_item("%s  [%s]  %s/%s episodes" % (s.get("title"), ON if s.get("monitored") else OFF,
                                               st.get("episodeFileCount", 0),
                                               st.get("totalEpisodeCount", 0)),
                 (s.get("overview") or "")[:500], art_of(s),
                 action="series", sid=s["id"])
    end()


def series(sid):
    ok, s = api("sonarr", "/api/v3/series/%s" % sid)
    if not ok:
        fail("Series", s)
        end()
        return
    st = s.get("statistics", {})
    missing = (st.get("totalEpisodeCount", 0) or 0) - (st.get("episodeFileCount", 0) or 0)
    add_item("Monitoring is %s  -  tap to turn it %s"
             % (ON if s.get("monitored") else OFF, "OFF" if s.get("monitored") else "ON"),
             "Monitored means Sonarr grabs new episodes by itself every 15 minutes.",
             action="togglemon", sid=sid)
    add_item("Search for all %d missing episodes" % missing,
             "Asks the indexers for everything this series is missing.",
             action="seriessearch", sid=sid)
    for season in s.get("seasons", []):
        n = season.get("seasonNumber")
        sst = season.get("statistics", {}) or {}
        add_item("Season %s  [%s]  %s/%s" % (n, ON if season.get("monitored") else OFF,
                                             sst.get("episodeFileCount", 0),
                                             sst.get("totalEpisodeCount", 0)),
                 "Search this season, or toggle whether Sonarr watches it.",
                 action="season", sid=sid, season=n)
    end()


def season(sid, number):
    add_item("Search season %s now" % number, "Grab everything missing in this season",
             action="seasonsearch", sid=sid, season=number)
    add_item("Toggle monitoring for season %s" % number, "",
             action="toggleseason", sid=sid, season=number)
    end()


def togglemon(sid):
    ok, s = api("sonarr", "/api/v3/series/%s" % sid)
    if not ok:
        fail("Series", s)
        end()
        return
    new = not s.get("monitored")
    s["monitored"] = new
    for season_ in s.get("seasons", []):
        season_["monitored"] = new
    ok, res = api("sonarr", "/api/v3/series/%s" % sid, s, method="PUT")
    notify("%s monitoring %s" % (s.get("title"), "ON" if new else "OFF")) if ok else fail("Update", res)
    xbmc.executebuiltin("Container.Refresh")
    end()


def toggleseason(sid, number):
    ok, s = api("sonarr", "/api/v3/series/%s" % sid)
    if not ok:
        fail("Series", s)
        end()
        return
    new = None
    for season_ in s.get("seasons", []):
        if str(season_.get("seasonNumber")) == str(number):
            new = not season_.get("monitored")
            season_["monitored"] = new
    ok, res = api("sonarr", "/api/v3/series/%s" % sid, s, method="PUT")
    notify("Season %s monitoring %s" % (number, "ON" if new else "OFF")) if ok else fail("Update", res)
    end()


def command(service, payload, what):
    if not confirm_download(what):
        end()
        return
    ok, res = api(service, "/api/v3/command", payload)
    notify("Searching for %s" % what, 5000) if ok else fail("Search", res)
    end()


def queue():
    rows = []
    for service, label in (("sonarr", "TV"), ("radarr", "Movie")):
        ok, data = api(service, "/api/v3/queue?pageSize=50")
        if not ok:
            rows.append(("[COLOR red]%s queue unavailable[/COLOR]" % label, str(data)))
            continue
        for rec in (data or {}).get("records", []):
            size = rec.get("size") or 0
            left = rec.get("sizeleft") or 0
            pct = 100.0 * (size - left) / size if size else 0.0
            rows.append(("%s  %.0f%%  %s" % (label, pct, (rec.get("title") or "?")[:70]),
                         "status: %s\nsize: %.2f GB\nremaining: %.2f GB"
                         % (rec.get("status"), size / 1e9, left / 1e9)))
    if not rows:
        rows = [("Nothing downloading", "The queue is empty")]
    for label, plot in rows:
        add_item(label, plot, action="queue")
    end()


def wanted():
    ok, data = api("sonarr", "/api/v3/wanted/missing?includeSeries=true&pageSize=60&sortKey=airDateUtc&sortDirection=descending")
    if not ok:
        fail("Wanted list", data)
        end()
        return
    recs = (data or {}).get("records", [])
    if not recs:
        add_item("Nothing missing", "Either everything is on disk, or no series is monitored.\n"
                                    "Monitoring is per-series under 'My shows'.", action="wanted")
        end()
        return
    for rec in recs:
        title = (rec.get("series") or {}).get("title", "?")
        add_item("%s  S%02dE%02d  %s" % (title, rec.get("seasonNumber", 0),
                                         rec.get("episodeNumber", 0), rec.get("title", "?")),
                 (rec.get("overview") or "")[:400],
                 action="epsearch", eid=rec["id"],
                 what="%s S%02dE%02d" % (title, rec.get("seasonNumber", 0), rec.get("episodeNumber", 0)))
    end()


def movies():
    ok, data = api("radarr", "/api/v3/movie")
    if not ok:
        fail("Movie list", data)
        end()
        return
    if not data:
        add_item("No movies yet", "Use 'Search for a movie' to add one", action="root")
    for m in sorted(data, key=lambda x: x.get("sortTitle") or x.get("title", "")):
        have = "on disk" if m.get("hasFile") else "missing"
        add_item("%s (%s)  [%s]  %s" % (m.get("title"), m.get("year") or "?",
                                        ON if m.get("monitored") else OFF, have),
                 (m.get("overview") or "")[:500], art_of(m),
                 action="moviemenu", mid=m["id"])
    end()


def moviemenu(mid):
    ok, m = api("radarr", "/api/v3/movie/%s" % mid)
    if not ok:
        fail("Movie", m)
        end()
        return
    add_item("Monitoring is %s  -  tap to turn it %s"
             % (ON if m.get("monitored") else OFF, "OFF" if m.get("monitored") else "ON"),
             "", action="togglemovie", mid=mid)
    add_item("Search for this film now", "", action="moviesearch", mid=mid,
             what=m.get("title", "?"))
    end()


def togglemovie(mid):
    ok, m = api("radarr", "/api/v3/movie/%s" % mid)
    if not ok:
        fail("Movie", m)
        end()
        return
    m["monitored"] = not m.get("monitored")
    ok, res = api("radarr", "/api/v3/movie/%s" % mid, m, method="PUT")
    notify("%s monitoring %s" % (m.get("title"), "ON" if m["monitored"] else "OFF")) if ok else fail("Update", res)
    end()


def rescan():
    xbmc.executebuiltin("UpdateLibrary(video)")
    notify("Kodi is rescanning /srv/media")
    end()


def main():
    args = dict(urllib.parse.parse_qsl(sys.argv[2][1:]))
    a = args.get("action")
    if a == "search":
        search(args.get("service", "sonarr"))
    elif a == "add":
        add(args.get("service", "sonarr"), args.get("ident"), args.get("title", "?"))
    elif a == "shows":
        shows()
    elif a == "series":
        series(args.get("sid"))
    elif a == "season":
        season(args.get("sid"), args.get("season"))
    elif a == "togglemon":
        togglemon(args.get("sid"))
    elif a == "toggleseason":
        toggleseason(args.get("sid"), args.get("season"))
    elif a == "seriessearch":
        command("sonarr", {"name": "SeriesSearch", "seriesId": int(args.get("sid"))},
                "all missing episodes")
    elif a == "seasonsearch":
        command("sonarr", {"name": "SeasonSearch", "seriesId": int(args.get("sid")),
                           "seasonNumber": int(args.get("season"))},
                "season %s" % args.get("season"))
    elif a == "epsearch":
        command("sonarr", {"name": "EpisodeSearch", "episodeIds": [int(args.get("eid"))]},
                args.get("what", "that episode"))
    elif a == "moviesearch":
        command("radarr", {"name": "MoviesSearch", "movieIds": [int(args.get("mid"))]},
                args.get("what", "that film"))
    elif a == "movies":
        movies()
    elif a == "moviemenu":
        moviemenu(args.get("mid"))
    elif a == "togglemovie":
        togglemovie(args.get("mid"))
    elif a == "queue":
        queue()
    elif a == "wanted":
        wanted()
    elif a == "rescan":
        rescan()
    else:
        root()


if __name__ == "__main__":
    main()
