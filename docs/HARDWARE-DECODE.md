# Hardware decode on the GeForce 9400M (VP3)

1080p H.264 decodes in hardware on this GPU, but **only if all three of the following
are true at once**. Any one missing and you silently fall back to software decoding,
which costs ~60% of one CPU core and makes the machine unpleasant.

Measured, 1080p H.264: **Kodi software ≈60% of one core → mpv VAAPI ≈10%**.

## 1. VP3 falcon microcode

nouveau cannot ship this microcode for licensing reasons, so no distro package contains
it — and neither does this repo. The 17 files are extracted on your own machine from the
**NVIDIA 340.108** legacy driver using the envytools `extract_firmware.py`, by
`scripts/extract-firmware.sh` (which `install-firmware.sh` runs automatically if the files
are missing). They then live in `firmware/nouveau/` and get installed to
`/lib/firmware/nouveau/`.

Symptom when missing:

```
nouveau 0000:02:00.0: nvac_fuc084 failed with error -2
```

and zero decode profiles in `vainfo` / `vdpauinfo`.

Install with `sudo ./scripts/install-firmware.sh`, then **reboot** — `modprobe -r nouveau`
fails because fbcon pins the module.

> These files are **not package-managed**. If `/lib/firmware/nouveau` is ever emptied —
> by a reinstall, or a cleanup script — hardware decode dies silently. That is the single
> most likely way to lose this setup.

Note on variants: `re-vp2` is the older extraction variant, but both it and VP3 have
identical offsets and lengths for these files, so either source works.

## 2. Patched Mesa

Add [`ppa:francesco-stimola/mesa-nouveau-fixes`](https://launchpad.net/~francesco-stimola/+archive/ubuntu/mesa-nouveau-fixes)
and install `26.0.8-1ubuntu0.3+nvfix4` or newer. It is Ubuntu's own Mesa plus ~13 nouveau
patches. Revert with `ppa-purge` if needed. That repo's README lists NVAC/VP3 explicitly
and predicted every symptom seen on this machine.

Why it is required: **upstream Mesa 24.1 and later leak decoder engine objects whenever a
decoder is re-created.** A seek re-creates the decoder, so with stock Mesa every seek
fails one frame:

```
Failed to upload decode parameters: 2 (resource allocation failed)
… then: invalid VAContextID
```

which shows up as a **green flash on every seek**. Patch 0003 fixes that, 0007 fixes
green/magenta output from video post-processing, and 0001 silences the
`SURF_HEIGHT_OVERRUN` traps.

Also note: **Mesa 25.3 removed the VDPAU frontend entirely.** On Ubuntu 26.04 (Mesa 26)
`mesa-vdpau-drivers` and `mesa-va-drivers` no longer exist as packages — they are folded
into `mesa-libgallium`. VA-API is the path this setup uses; VDPAU is only ever useful here
as a diagnostic, and see the warning below before you try it.

## 3. The GPU clock boot parameter

nouveau never changes clocks on its own, and the VBIOS on this machine leaves the GPU at
the **middle** performance level `0e` — core 350 / shader 800 / **vdec 350 MHz**. Level
`0f` gives core 450 / shader 1150 / **vdec 450 MHz**.

Set it on the kernel command line in `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="... nouveau.config=NvClkMode=0xf"
```

then `sudo update-grub` and reboot. `scripts/install-firmware.sh` does this for you and
backs the original up to `/etc/default/grub.bak-preclk`.

> **Never change pstate at runtime** via `/sys/kernel/debug/dri/*/pstate`. Upstream
> documents GPUs left hung doing exactly that. Use the boot parameter.

## Verifying

```sh
vainfo 2>&1 | grep -i h264        # must list H264 decode entrypoints
hwdecode status
```

During playback, `mpv` should report `hwdec: vaapi`. If the GPU is doing the work, CPU use
for a 1080p file sits near 10% of one core rather than 60%.

## Why Kodi cannot do this itself

Kodi's own VDPAU path needs `GL_NV_vdpau_interop`, which only the proprietary driver
provides, and Ubuntu's X11/GLX Kodi build has **no VAAPI compiled in at all** (zero
`vaapi` lines appear in `kodi.log`). There are no `kodi-gbm` or `kodi-wayland` packages in
26.04 either. So Kodi hands video files to **mpv** instead, via
`config/playercorefactory.xml`. That is what `hwdecode on|off` toggles.

## The one thing that will hang your machine

**Never use mpv `vo=vdpau` on this GPU.** It wedges nouveau: the process goes into
unkillable D-state, X stops answering clients, and you get a kernel trace in
`nouveau_channel_del` / `nouveau_drm_postclose`. Only a reboot clears it.

Use `vo=gpu` with `hwdec=vaapi`. That is the good path, and it is what the shipped
`playercorefactory.xml` configures.

## Known cosmetic noise

Hardware-decoded playback logs roughly 23 lines per 25 seconds of:

```
nouveau gr: DATA_ERROR [XY_OUT_OF_BOUNDS]
nouveau gr: TRAP_PROP [SURF_HEIGHT_OVERRUN]
```

These are VAAPI-specific — zero with software decode, zero at idle, and identical on GLX
and x11egl, so it is not a context problem. Most likely NV12 1080→1088 row alignment.
Upstream describes VP3 support as half-finished. Playback is unaffected; if you ever do
see visual artifacts, `hwdecode off` falls back to software.
