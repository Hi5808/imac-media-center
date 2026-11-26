# iMac9,1 Media Center

Turns a 2009 iMac (`iMac9,1`) into a Kodi appliance that plays 1080p H.264 with
**hardware decoding**, and runs a full Sonarr/Radarr/Prowlarr/Transmission stack
operable from the couch with a remote — no keyboard, no desktop, no browser.

This machine is slow and its GPU is barely supported. Everything here exists because
the obvious approach did not work. Read [docs/HARDWARE-DECODE.md](docs/HARDWARE-DECODE.md)
before touching graphics; it is the part that took the longest to get right.

## What this hardware actually is

| | |
|---|---|
| Model | iMac9,1 (early 2009), 20" or 24" |
| CPU | Core 2 Duo P7550 — **SSE4.1, no SSE4.2, no POPCNT** |
| GPU | GeForce 9400M (MCP79, **NVAC**), VP3 video engine |
| Panel | built-in LVDS, 1680x1050 |
| Audio | Realtek ALC889A, plus a separate internal `Bass Speaker` mixer control |
| OS tested | Ubuntu 26.04.1, nouveau (the proprietary driver is long EOL for this GPU) |

**The CPU baseline matters.** No SSE4.2 means anything built for `x86-64-v2` will not
run. In practice:

- Bun will not run. Node will.
- Modern Chrome/Chromium will not run, so **FlareSolverr cannot run on this box** —
  it drives a headless Chrome. Run it on another machine and point Prowlarr at it.
- The .NET `*arr` apps **do** run fine. The SSE4.2 ceiling does not apply to them;
  this was verified by running them, not by reading docs.

**The codec ceiling is silicon:** H.264 (High, up to L4.1, max 2032x2048), MPEG-2 and
VC-1 only. There is **no HEVC, VP9 or AV1 decoding**, in any software, ever. Blocking
those formats in the `*arr` apps is not a preference, it is a requirement — see
[docs/ARR-STACK.md](docs/ARR-STACK.md).

## Layout it builds

```
Kodi 21.3 as the shell (sddm autologin, no desktop)
  └─ video playback handed to mpv (hwdec=vaapi) via playercorefactory.xml
/srv/media/{Movies,TV,Music,Pictures}   ← Kodi library + *arr destination
/srv/downloads/{complete,incomplete}    ← same filesystem, so imports hardlink
Transmission :9091   Prowlarr :9696   Sonarr :8989   Radarr :7878
Samba: //<host>/media and //<host>/downloads
```

To move to a bigger disk, mount it at `/srv/media`. Nothing references any other path.

## Install

There is a phased installer. Read [docs/HARDWARE-DECODE.md](docs/HARDWARE-DECODE.md)
first — the hardware-decode phase needs a **reboot in the middle**, so it is not a
single unattended run.

```sh
git clone https://github.com/Hi5808/imac-media-center.git
cd imac-media-center
./install.sh                 # the phase menu
sudo ./install.sh all        # deps + firmware, then stops at the reboot gate
# --- reboot ---
sudo ./install.sh kodi arrs jellyfin dashboard addon alert
./install.sh status          # verify
```

Each phase is idempotent, so re-running one is safe. You can also run any phase on
its own (e.g. `sudo ./install.sh alert`).

### About the GPU firmware

Hardware H.264 decode needs 17 NVIDIA VP3 microcode files. **This repo does not
ship them** — they are proprietary and cannot be redistributed. The firmware phase
runs [`scripts/extract-firmware.sh`](scripts/extract-firmware.sh), which downloads
NVIDIA's own legacy `340.108` driver and extracts them on your machine (the
standard [nouveau workflow](https://nouveau.freedesktop.org/VideoAcceleration.html)).
See [NOTICE.md](NOTICE.md).

Then follow, in order:

1. [docs/HARDWARE-DECODE.md](docs/HARDWARE-DECODE.md) — the three things that must all
   be true before anything is decoded in hardware. Start here.
2. [docs/KODI-SHELL.md](docs/KODI-SHELL.md) — Kodi as the shell, mpv handoff, library setup.
3. [docs/ARR-STACK.md](docs/ARR-STACK.md) — the download stack, and the codec filtering
   that keeps unplayable releases out.
4. [docs/ADDON.md](docs/ADDON.md) — the "Find Media" add-on, so the stack is driven by remote.
5. [docs/STREAMING-PIPELINE.md](docs/STREAMING-PIPELINE.md) — Jellyfin/Jellyseerr/Homepage: stream the
   same library to phones, a request portal, and one dashboard over it all.
6. [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — the failure modes, with their symptoms.

## Contents

| Path | What |
|---|---|
| `install.sh` | the phased orchestrator — `all`, or any of `deps firmware kodi arrs jellyfin dashboard addon alert`, plus `status` |
| `addon/` | "Find Media" Kodi add-on (`plugin.video.arrsearch`) — search/add shows and films, monitoring toggles, live queue, wanted list, library rescan |
| `firmware/nouveau/` | where the 17 VP3 microcode files land after extraction. **Not shipped** — see `scripts/extract-firmware.sh` and NOTICE.md |
| `scripts/hwdecode` | `hwdecode on\|off\|status` — toggles the mpv VAAPI handoff |
| `scripts/extract-firmware.sh` | downloads NVIDIA's 340.108 driver and extracts the VP3 microcode on your machine |
| `scripts/install-firmware.sh` | installs the microcode (auto-extracting first if needed) and sets the GPU clock boot parameter |
| `scripts/install-addon.sh` | installs the add-on without clobbering saved API keys |
| `config/playercorefactory.xml` | the Kodi → mpv handoff |
| `config/homepage/` | Homepage dashboard: `settings.yaml` (layout/order) + `services.yaml.example` (widgets, keys redacted) |
| `config/systemd/disk-alert.*` | hourly disk-space alert unit + timer |
| `scripts/disk-alert.sh` | warns on-screen (Kodi) + syslog when `/` runs low |
| `config/*.example` | grub, sddm and AppArmor fragments, with the values that matter marked |
| `docs/README-MEDIACENTER.md` | the original on-box operator notes |

## Security note

No credentials are committed. The `*arr` API keys live in Kodi's `addon_data`, outside
the add-on directory, so reinstalling the add-on keeps them — and keeps them out of git.
The example configs use `CHANGEME` where a password belongs. Set your own; do not reuse
the placeholders.

## Status

Working and in daily use: hardware decode confirmed, the stack searches, grabs, imports
and refreshes the Kodi library on its own, and the add-on drives all of it from a remote.
Known rough edges are listed in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) —
most notably ~23 harmless nouveau `XY_OUT_OF_BOUNDS` log lines per 25s of hardware-decoded
playback, which upstream considers VP3 support being half-finished.
