# iMac Media Center

iMac9,1 (2009), Core 2 Duo P7550, 7.5GB RAM, GeForce 9400 (MCP79/NVAC),
Ubuntu 26.04.1, single 149GB disk. Kodi runs as the shell - there is no desktop.

## What runs

| thing | where | notes |
|---|---|---|
| Kodi 21.3 | the screen | the whole UI; started by sddm autologin |
| mpv | launched by Kodi | does the actual video playback, for hardware decode |
| Transmission | :9091 | transfer backend for the *arrs (user mac) |
| Prowlarr | :9696 | indexer manager, syncs to Sonarr + Radarr |
| Sonarr | :8989 | TV, root folder /srv/media/TV |
| Radarr | :7878 | movies, root folder /srv/media/Movies |
| Samba | //imac/media, //imac/downloads | user mac |

## Media layout

    /srv/media/{Movies,TV,Music,Pictures}   library (Kodi sources point here)
    /srv/downloads/{complete,incomplete}    transmission writes here

Both are on / so the *arrs can hardlink instead of copying.
Group `media` is shared by mac, debian-transmission, sonarr, radarr; dirs are 2775 setgid.

### Expanding or replacing the disk
The paths above are what everything references. To move the library to a
bigger disk, mount it at /srv/media (and optionally /srv/downloads) and
nothing else needs changing - no Kodi, *arr or Samba reconfiguration.

## Hardware video decode - the important part

The GeForce 9400 has a VP3 decoder (H.264 High up to level 4.1, MPEG-2, VC-1).
No HEVC, VP9 or AV1 - that is silicon, not software.

Getting to it required two non-obvious things:

1. **Firmware.** nouveau cannot ship VP3 falcon microcode (NVIDIA licence).
   Without it the kernel says `nvac_fuc084 failed with error -2` and exposes
   zero decode profiles. The files in /lib/firmware/nouveau were extracted
   from NVIDIA 340.108 using a Python 3 port of envytools' extract_firmware.py.
   THESE ARE NOT PACKAGE-MANAGED. If /lib/firmware/nouveau is ever emptied,
   hardware decode silently disappears.

2. **mpv does the playback, not Kodi.** Kodi cannot use this hardware:
   its VDPAU path needs the GL_NV_vdpau_interop extension (proprietary driver
   only) and this Kodi build has no VAAPI support. So
   ~/.kodi/userdata/playercorefactory.xml hands every video to mpv, which
   uses VAAPI.

Measured, 1080p H.264:
  - Kodi internal software decode: 60% of one core
  - mpv with VAAPI:                10% of one core

### Hardware decode: what makes it work
All THREE are required. Remove any one and you get software decode or green frames.

1. /lib/firmware/nouveau   (VP3 ucode from NVIDIA 340.108, see above)

2. Patched Mesa: ppa:francesco-stimola/mesa-nouveau-fixes -> 26.0.8-1ubuntu0.3+nvfix4
   Stock Mesa 24.1 and later leaks decoder engine objects when a decoder is
   recreated, so every SEEK failed one frame:
       Failed to upload decode parameters: 2 (resource allocation failed)
       h264: Failed to end picture decode after error: 5 (invalid VAContextID)
   which showed as a green flash when fast-forwarding. The patches also removed
   the SURF_HEIGHT_OVERRUN kernel traps logged on every video start.
   Revert with:  sudo ppa-purge ppa:francesco-stimola/mesa-nouveau-fixes

3. nouveau.config=NvClkMode=0xf on the kernel cmdline (set in /etc/default/grub,
   original saved as grub.bak-preclk).
   nouveau never changes GPU clocks by itself, and the VBIOS left this card on the
   MIDDLE level: vdec 350MHz instead of 450, shaders 800 instead of 1150.
   Check:  sudo cat /sys/kernel/debug/dri/*/pstate      (the * marks the active level)
   NEVER write to pstate on a running desktop - upstream documents GPUs hung by that.

Measured with subtitles on and seeking: 10.3% of one core, versus 52.6% software.
Zero dropped frames, zero kernel traps, a/v sync about 70 microseconds.

Keep vo=gpu with profile=fast in ~/.config/mpv/mpv.conf:
   - profile=fast is load-bearing: mpv's default scaler drops ~175 frames per 30s here.
   - vo=vaapi is cheaper with no subtitles, but costs twice as much once subs render.

### DO NOT use vo=vdpau in mpv
It hangs the nouveau driver: the process goes into unkillable D-state,
X stops answering, and only a reboot clears it. Learned the hard way.

## Tradeoff of the external player
Because mpv plays the video rather than Kodi, you lose Kodi's in-player OSD,
its subtitle menus and reliable resume points. mpv has its own OSD and keys.
To go back to Kodi's internal player (software decode), remove
~/.kodi/userdata/playercorefactory.xml and restart Kodi.

## Handy commands

    hwdecode on|off|status          switch hardware/software decode
    ~/verify-hwdecode.sh            play a clip and measure CPU (needs a file)
    systemctl restart sddm          restart Kodi
    systemctl status sonarr radarr prowlarr transmission-daemon

## Getting the desktop back
/etc/sddm.conf sets Session=kodi.desktop. Change it to Session=Lubuntu and
restart sddm. The original file is at /etc/sddm.conf.bak-prekodi.

## The acquisition stack (configured and tested)

Prowlarr (:9696) searches indexers -> Sonarr (:8989) / Radarr (:7878) pick a release
-> Transmission (:9091) moves the bytes into /srv/downloads/complete
-> the *arr hardlinks + renames it into /srv/media -> Kodi library updates itself.

Configured:
  - Indexers in Prowlarr: Internet Archive, LimeTorrents, Nyaa.si, The Pirate Bay, YTS
    (public, no account). Synced down automatically: Sonarr gets the TV-category ones,
    Radarr the movie-category ones. 1337x and EZTV were refused by Prowlarr's own
    connectivity test (CloudFlare); they would need FlareSolverr.
  - Download client: Transmission on both, user mac / CHANGEME.
  - Root folders: Sonarr /srv/media/TV, Radarr /srv/media/Movies.
  - Kodi notification on both: finishes an import -> Kodi refreshes its library
    (uses the Kodi web server on :8080, kodi / CHANGEME).
  - THIS BOX CANNOT DECODE HEVC, 4K, AV1 or VP9. So:
      Sonarr: release profile "No HEVC or 4K" ignores x265/HEVC/h265/2160p/4K/AV1/VP9/XviD/DivX
      Radarr: custom format "Unplayable here (x265/HEVC/4K)" scored -10000 in the
              HD-1080p and HD-720p/1080p profiles
    Keep using quality profile 6 (HD - 720p/1080p) for anything added by hand.
  - Kodi library: content types set directly in MyVideos131.db (the GUI is the usual
    way; the path table holds strContent + strScraper). Movies use
    metadata.themoviedb.org.python, TV uses metadata.tvshows.themoviedb.org.python.
    Backup of the pre-change db: MyVideos131.db.bak-precontent.

Verified end to end on 2026-11-17: Sonarr searched S01E02 through Prowlarr and got a
1080p H.264 release back from LimeTorrents, correctly not rejected. Nothing was grabbed.

If a 4K/HEVC file does end up here, transcode it on a faster machine first:
  ffmpeg -i in.mkv -map 0:v:0 -map 0:a:0 \
    -vf "scale=1920:-2:flags=lanczos,zscale=t=linear:npl=100,format=gbrpf32le,\
zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p" \
    -c:v libx264 -preset fast -crf 20 -profile:v high -level 4.1 -c:a copy out.mkv
(level 4.1 and 8-bit yuv420p are what VP3 can decode; 1080p is 8160 macroblocks
against its 8190 limit, so it just fits.)

## Still to do
- Nothing blocking. Optional: FlareSolverr for CloudFlare-protected indexers;
  an SSD would make seeking far better than more capacity (see the HDD note above).
