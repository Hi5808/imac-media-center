# Third-party components

This repository contains only original scripts, configuration and documentation
(MIT licensed, see LICENSE). It deliberately does **not** redistribute:

- **NVIDIA VP3 microcode** — the 17 falcon firmware files required for hardware
  video decode are proprietary NVIDIA firmware and may not be redistributed.
  `scripts/extract-firmware.sh` downloads NVIDIA's own legacy 340.108 driver and
  extracts them on your machine, using the GPL `extract_firmware.py` from the
  envytools project (fetched at install time, not vendored):
  https://github.com/envytools/firmware

- **Jellyfin, Homepage, Jellyseerr, the Servarr apps** — installed from their own
  upstream repositories / Docker images under their respective licenses.
