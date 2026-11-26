#!/bin/bash
# Install the "Find Media" Kodi add-on. Saved settings (including API keys) live in
# Kodi's addon_data directory, so they survive this. Run as the Kodi user, not root.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/addon"
DST="$HOME/.kodi/addons/plugin.video.arrsearch"
DATA="$HOME/.kodi/userdata/addon_data/plugin.video.arrsearch"

[ -f "$SRC/addon.xml" ] || { echo "error: $SRC/addon.xml not found" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
    echo "error: run as the Kodi user, not root" >&2
    exit 1
fi

ver=$(sed -n 's/.*[[:space:]]version="\([0-9][0-9.]*\)".*/\1/p' "$SRC/addon.xml" | tail -1)
echo "==> installing plugin.video.arrsearch ${ver:-?} to $DST"

mkdir -p "$DST"
cp -r "$SRC"/addon.xml "$SRC"/default.py "$DST"/
[ -d "$SRC/resources" ] && cp -r "$SRC/resources" "$DST"/

if [ -f "$DATA/settings.xml" ]; then
    echo "==> kept existing settings (API keys) in $DATA/settings.xml"
else
    echo "==> no saved settings yet — set your Sonarr/Radarr URLs and API keys"
    echo "    in the add-on's settings once Kodi has loaded it"
fi

cat <<'EOF'

Installed. Kodi re-reads the plugin on each invocation, so no restart is needed,
but a newly added add-on has to be enabled once:

    curl -s -u kodi:YOURPASSWORD -H 'Content-Type: application/json' \
      -d '{"jsonrpc":"2.0","id":1,"method":"Addons.SetAddonEnabled",
           "params":{"addonid":"plugin.video.arrsearch","enabled":true}}' \
      http://127.0.0.1:8080/jsonrpc

See docs/ADDON.md.
EOF
