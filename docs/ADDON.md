# "Find Media" Kodi add-on

`plugin.video.arrsearch` — drives the whole download stack from a remote, so no browser or
keyboard is needed. Search for and add shows and films, toggle monitoring per series or
season, trigger searches, watch the live queue, see the wanted list, and rescan the library.

## Install

```sh
./scripts/install-addon.sh
```

It copies the add-on into `~/.kodi/addons/plugin.video.arrsearch` and leaves saved settings
alone. Then enable it (Kodi must be running):

```sh
curl -s -u kodi:CHANGEME -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"Addons.SetAddonEnabled",
       "params":{"addonid":"plugin.video.arrsearch","enabled":true}}' \
  http://127.0.0.1:8080/jsonrpc
```

Set your Sonarr and Radarr URLs and API keys in the add-on's settings.

**Your API keys are not stored in the add-on directory.** They live in
`~/.kodi/userdata/addon_data/plugin.video.arrsearch/settings.xml`, which means
reinstalling or updating the code keeps them — and keeps them out of git.

## Menu

| Entry | Action |
|---|---|
| Search for a TV show / a movie | look up by name and add it |
| My shows / My movies | per-item menus: monitoring toggles, season and episode search |
| Downloading now | live queue with progress |
| Wanted / missing TV | clickable — selecting an episode searches for it |
| Refresh Kodi library | rescan `/srv/media` |

Search actions ask for confirmation first, because they start real downloads.

## Testing it without a TV

`Files.GetDirectory` over JSON-RPC actually executes the plugin, which makes it a good
headless test:

```sh
curl -s -u kodi:CHANGEME -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"Files.GetDirectory",
       "params":{"directory":"plugin://plugin.video.arrsearch/?action=queue","media":"video"}}' \
  http://127.0.0.1:8080/jsonrpc
```

Useful actions: `shows`, `movies`, `queue`, `wanted`, `series&sid=N`,
`season&sid=N&season=M`.

**Do not test `action=search` or the `*search` actions this way** — they open modal dialogs
on the TV and will sit there waiting for someone with a remote.

Note that an **unknown action silently renders the root menu** rather than erroring, so if a
probe returns the 7 root entries, check your action name before concluding the entry is
broken.

## Version history

**1.1.1** — fixed three bugs found by probing every entry point:

1. The dispatcher had lost its `queue` and `wanted` branches, so both menu entries silently
   fell through to the root menu. The functions existed but were unreachable.
2. `add_item(label, ...)` takes `label` positionally, so passing `label=` as a *URL*
   parameter raised `TypeError: got multiple values for argument 'label'` and killed the
   entire Wanted list. That URL parameter is now called `what`.
3. Sonarr's `/api/v3/wanted/missing` omits the series object unless you pass
   `includeSeries=true`, so every row read `?  S01E09` instead of the show's name.

**1.1.0** — monitoring toggles, season/episode search, clickable wanted list, confirmations.

**1.0.0** — first working version.

## Developing

Kodi re-reads the plugin's Python on **every invocation**, so edits take effect without
restarting Kodi. Errors land in `~/.kodi/temp/kodi.log` — grep for `arrsearch`, `Traceback`
and `Error Contents`.
