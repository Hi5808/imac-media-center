#!/bin/bash
# Extract the VP3 falcon microcode for the GeForce 9400M (NV98/NVAA/NVAC) from
# NVIDIA's legacy 340.108 driver, using the GPL envytools extractor.
#
# Why: NVIDIA's license forbids redistributing these binaries, so this repo does
# not ship them. This is the standard nouveau workflow — you extract them from
# NVIDIA's own driver on your own machine. See docs/HARDWARE-DECODE.md and
# https://nouveau.freedesktop.org/VideoAcceleration.html
#
# Run as root. It downloads ~75 MB (the driver) once.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run with sudo" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$HERE/firmware/nouveau"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

DRIVER_VER="340.108"
DRIVER_RUN="NVIDIA-Linux-x86-${DRIVER_VER}.run"
DRIVER_URL="https://us.download.nvidia.com/XFree86/Linux-x86/${DRIVER_VER}/${DRIVER_RUN}"
EXTRACT_URL="https://raw.githubusercontent.com/envytools/firmware/master/extract_firmware.py"

need() { command -v "$1" >/dev/null || { echo "error: need '$1' (apt install $2)" >&2; exit 1; }; }
need curl curl
need python3 python3

echo "==> fetching envytools extract_firmware.py (GPL)"
curl -fsSL "$EXTRACT_URL" -o "$WORK/extract_firmware.py"

# Allow a locally-provided driver to skip the download:
#   scripts/extract-firmware.sh /path/to/NVIDIA-Linux-x86-340.108.run
if [ "${1:-}" ] && [ -f "$1" ]; then
    cp "$1" "$WORK/$DRIVER_RUN"
    echo "==> using provided driver: $1"
else
    echo "==> downloading $DRIVER_RUN from NVIDIA (~75 MB)"
    curl -fL --progress-bar "$DRIVER_URL" -o "$WORK/$DRIVER_RUN"
fi

echo "==> unpacking driver"
( cd "$WORK" && sh "./$DRIVER_RUN" --extract-only >/dev/null )
DRIVER_DIR="$WORK/NVIDIA-Linux-x86-${DRIVER_VER}"
[ -d "$DRIVER_DIR" ] || { echo "error: driver did not unpack to $DRIVER_DIR" >&2; exit 1; }

echo "==> extracting microcode"
( cd "$DRIVER_DIR" && python3 "$WORK/extract_firmware.py" )

# The extractor writes nv* and vuc-* files into the driver dir's nouveau/ output.
OUT="$DRIVER_DIR/nouveau"
[ -d "$OUT" ] || OUT="$DRIVER_DIR"
install -d -m 0755 "$DST"
found=0
for f in nv98_bsp nv98_fuc084 nv98_fuc085 nv98_fuc086 nv98_ppp nv98_vp \
         nvaa_fuc084 nvaa_fuc085 nvaa_fuc086 nvac_fuc084 nvac_fuc085 nvac_fuc086 \
         vuc-vp3-h264-0 vuc-vp3-mpeg12-0 vuc-vp3-vc1-0 vuc-vp3-vc1-1 vuc-vp3-vc1-2; do
    src="$(find "$OUT" -name "$f" -print -quit 2>/dev/null || true)"
    if [ -n "$src" ]; then
        install -m 0644 "$src" "$DST/$f"
        found=$((found+1))
    else
        echo "   warn: $f not produced" >&2
    fi
done

echo "==> extracted $found/17 microcode files to $DST"
if [ "$found" -lt 17 ]; then
    echo "error: extraction incomplete — see docs/HARDWARE-DECODE.md" >&2
    exit 1
fi
echo "==> done. Now run: sudo ./scripts/install-firmware.sh"
