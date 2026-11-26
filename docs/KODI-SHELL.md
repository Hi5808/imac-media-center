# Kodi as the shell

There is no desktop. sddm autologins straight into Kodi 21.3.

## The sddm trap

**`/etc/sddm.conf` beats `/etc/sddm.conf.d/*`** — sddm reads the main file last, so it
wins. Lubuntu ships one containing `Session=Lubuntu`, which means a drop-in file in
`sddm.conf.d` is **silently ignored**. Edit the main file.

See `config/sddm.conf.example`. Back up the original first; here it went to
`/etc/sddm.conf.bak-prekodi`. To get the desktop back, set `Session=Lubuntu` there.

## Restarting Kodi

`systemctl restart sddm`, or starting before the old process has exited, can leave **two
`kodi.bin` processes**. That makes JSON-RPC `Files.GetDirectory` hang and the UI misbehave.

Always wait for `pgrep -x kodi.bin` to come back empty before `systemctl start sddm`.

## Video handed to mpv

`config/playercorefactory.xml` → `~/.kodi/userdata/playercorefactory.xml` makes Kodi hand
video files to mpv with `hwdec=vaapi`, because Kodi's own build cannot use this GPU's
decoder. See [HARDWARE-DECODE.md](HARDWARE-DECODE.md). `hwdecode on|off|status` toggles it.

## Library content types are not in a config file

This one is easy to lose hours to. Kodi's per-path content type lives in the SQLite
database, **not** in `sources.xml`: table `path`, columns `strContent` and `strScraper`, in
`~/.kodi/userdata/Database/MyVideos131.db`.

**Kodi must be stopped before you edit it**, or it will overwrite your changes on exit.

| Path | `strContent` | `strScraper` | `scanRecursive` |
|---|---|---|---|
| `/srv/media/Movies/` | `movies` | `metadata.themoviedb.org.python` | `2147483647` |
| `/srv/media/TV/` | `tvshows` | `metadata.tvshows.themoviedb.org.python` | `0` |

Set `strSettings` to `<settings />`. Back the database up first.

Then trigger a scan over JSON-RPC rather than from the UI:

```sh
curl -s -u kodi:CHANGEME -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"VideoLibrary.Scan"}' \
  http://127.0.0.1:8080/jsonrpc
```

## Audio

Weak output here turned out to be **stacked attenuation**: the PipeWire sink was at 0.40
*and* ALSA `Master` at 64%, leaving about 26% of available output. Set both to unity:

```sh
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0
amixer -c 0 sset Master 100%
sudo alsactl store          # persist
```

That was about 3.8x louder. The codec is a Realtek **ALC889A** on card 0, and this iMac has
a **separate `Bass Speaker` control** for the internal subwoofer — check that too, along
with `Speaker` and `PCM`. `Channel Mode` should be `2ch`.

## Kodi rewrites its own config

Kodi overwrites `guisettings.xml` when it exits. Stop the service before editing it, or
your changes vanish.
