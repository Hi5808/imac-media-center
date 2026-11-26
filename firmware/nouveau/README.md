# VP3 microcode is NOT shipped here (on purpose)

These 17 falcon microcode files are **proprietary NVIDIA firmware**. NVIDIA's
license does not allow redistributing them, so this repo cannot contain them.

You extract them from NVIDIA's own legacy driver on your machine — this is the
standard, legitimate nouveau workflow:

    sudo ./scripts/extract-firmware.sh

That script downloads the GPL `extract_firmware.py` (envytools) and the official
`NVIDIA-Linux-x86-340.108.run`, extracts the microcode, and installs it to
`/lib/firmware/nouveau/`. See docs/HARDWARE-DECODE.md.

Expected result in this directory after extraction:
  nv98_bsp nv98_fuc084 nv98_fuc085 nv98_fuc086 nv98_ppp nv98_vp
  nvaa_fuc084 nvaa_fuc085 nvaa_fuc086 nvac_fuc084 nvac_fuc085 nvac_fuc086
  vuc-vp3-h264-0 vuc-vp3-mpeg12-0 vuc-vp3-vc1-0 vuc-vp3-vc1-1 vuc-vp3-vc1-2
