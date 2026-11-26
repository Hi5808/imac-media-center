# Troubleshooting

Symptoms first, since that is how you meet them.

## Video

| Symptom | Cause |
|---|---|
| `nvac_fuc084 failed with error -2`, no profiles in `vainfo` | VP3 microcode missing from `/lib/firmware/nouveau`. Reinstall it and **reboot** |
| **Green flash on every seek**, `Failed to upload decode parameters: 2`, then `invalid VAContextID` | stock Mesa leaking decoder objects. You need the `mesa-nouveau-fixes` PPA |
| Green or magenta video | same PPA — patch 0007 |
| Playback smooth but CPU pinned near 60% of a core | hardware decode is not actually engaged. Check all three requirements |
| **Machine wedged**: unkillable D-state process, X not answering, `nouveau_channel_del` in dmesg | mpv was run with `vo=vdpau`. Only a reboot clears it. Never use that |
| ~23 `XY_OUT_OF_BOUNDS` / `SURF_HEIGHT_OVERRUN` lines per 25s | cosmetic, VAAPI-specific, harmless. Upstream VP3 support is half-finished |

## Kodi

| Symptom | Cause |
|---|---|
| Desktop loads instead of Kodi | `/etc/sddm.conf` is read **after** `sddm.conf.d/*` and wins. Edit the main file |
| JSON-RPC hangs, UI misbehaves | **two `kodi.bin` processes**. Wait for `pgrep -x kodi.bin` to be empty before starting sddm |
| Library shows files but no artwork or titles | per-path content type is unset. It lives in `MyVideos131.db`, not `sources.xml` |
| Config edits keep vanishing | Kodi rewrites `guisettings.xml` on exit. Stop it first |
| Audio much too quiet | stacked attenuation — check the PipeWire sink **and** ALSA `Master`, plus `Bass Speaker` |

## Downloads

| Symptom | Cause |
|---|---|
| Transmission: permission denied, then a segfault | AppArmor. Rules belong in `/etc/apparmor.d/local/transmission` |
| Torrent sits at 0%, `Idle`, `Have: None` | dead magnet — metadata never arrived. Remove and blocklist it |
| Download starts, then stops with 0 peers | also dead. Reaching a few percent proves nothing |
| Grabbed something unplayable (HEVC/4K) | codec filtering is missing or the wrong quality profile was used |
| Queue entries appear by themselves | `RssSync`, every 15 minutes, for any monitored episode |
| Several torrents stuck on `Queued` | normal — Transmission runs 5 at a time |
| Indexer fails Prowlarr's connectivity test | CloudFlare. Needs FlareSolverr **on another machine** |

## Things that are not package-managed

If the system is reinstalled or something cleans these up, they are gone and must be
restored from this repo or rebuilt:

- `/lib/firmware/nouveau/*` — 17 files. **Not shipped** (proprietary NVIDIA). Restore
  with `sudo ./scripts/extract-firmware.sh` (or `sudo ./install.sh firmware`).
- `/usr/lib/x86_64-linux-gnu/vdpau/libvdpau_gallium.so.1.0.0` — hand-built from Mesa
  **25.2.8**, with `libvdpau_nouveau.so{,.1}` symlinks beside it. **Not in this repo** — it
  is a compiled blob, and it was only ever used for diagnostics. VA-API is the path that
  matters. Rebuild it from Mesa 25.2.8 sources only if you specifically want VDPAU, and
  remember Mesa 25.3+ removed that frontend entirely.
- The `mesa-nouveau-fixes` PPA pin — reinstate the PPA.
- `nouveau.config=NvClkMode=0xf` in `/etc/default/grub`.
- `/usr/local/bin/hwdecode`. **In this repo.**

## Backups this setup leaves behind

| File | What it was |
|---|---|
| `/etc/sddm.conf.bak-prekodi` | pre-Kodi sddm config (restores the desktop) |
| `/etc/default/grub.bak-preclk` | grub before the GPU clock parameter |
| `MyVideos131.db.bak-precontent` | Kodi database before content types were set |
