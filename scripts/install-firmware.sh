#!/bin/bash
# Install VP3 falcon microcode for the GeForce 9400M (NVAC) and set the GPU clock
# boot parameter. A REBOOT is required afterwards: fbcon pins nouveau, so the module
# cannot be reloaded live.
#
# See docs/HARDWARE-DECODE.md. Must run as root.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run with sudo" >&2
    exit 1
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/firmware/nouveau"
DST=/lib/firmware/nouveau

count=$(find "$SRC" -maxdepth 1 -type f \( -name 'nv*' -o -name 'vuc-*' \) | wc -l)
if [ "$count" -lt 17 ]; then
    echo "==> microcode not present ($count/17) — extracting from NVIDIA driver first"
    "$HERE/scripts/extract-firmware.sh" "${1:-}"
    count=$(find "$SRC" -maxdepth 1 -type f \( -name 'nv*' -o -name 'vuc-*' \) | wc -l)
fi

echo "==> installing $count microcode files to $DST"
install -d -m 0755 "$DST"
install -m 0644 "$SRC"/nv* "$SRC"/vuc-* "$DST"/

# --- GPU clock level -------------------------------------------------------
# nouveau never reclocks by itself and the VBIOS leaves this GPU at the middle
# level 0e (vdec 350MHz). 0f gives vdec 450MHz. Never change pstate at runtime.
GRUB=/etc/default/grub
PARAM='nouveau.config=NvClkMode=0xf'

if grep -q 'NvClkMode' "$GRUB"; then
    echo "==> $GRUB already sets NvClkMode, leaving it alone"
else
    cp -n "$GRUB" "$GRUB.bak-preclk"
    echo "==> backed up $GRUB to $GRUB.bak-preclk"
    sed -i "s|^\(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*\)\"|\1 $PARAM\"|" "$GRUB"
    if ! grep -q 'NvClkMode' "$GRUB"; then
        echo "error: could not patch $GRUB — add '$PARAM' to" >&2
        echo "       GRUB_CMDLINE_LINUX_DEFAULT by hand" >&2
        exit 1
    fi
    echo "==> added $PARAM"
    update-grub
fi

cat <<'EOF'

Done. REBOOT now — the microcode cannot be loaded without it.

After rebooting, verify:
    vainfo 2>&1 | grep -i h264      # should list H264 decode entrypoints

Remember the other two requirements (docs/HARDWARE-DECODE.md):
  - the ppa:francesco-stimola/mesa-nouveau-fixes Mesa build
  - video handed to mpv via playercorefactory.xml  (scripts/hwdecode on)
EOF
