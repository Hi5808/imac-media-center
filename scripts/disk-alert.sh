#!/usr/bin/env bash
# disk-space-alert: warn on-screen (Kodi) + syslog when the media disk runs low.
# Runs from a systemd timer. Threshold = warn below AVAIL_MIN_GB free on /.
set -euo pipefail
MOUNT="/"
AVAIL_MIN_GB=15          # warn when free space drops below this
USE_MAX_PCT=90           # or when used% climbs above this
KODI_RPC="http://127.0.0.1:8080/jsonrpc"

read -r _ _ _ avail_kb usepct _ < <(df -P "$MOUNT" | tail -1 | awk "{print \$1,\$2,\$3,\$4,\$5,\$6}")
avail_gb=$(( avail_kb / 1024 / 1024 ))
use=${usepct%\%}

if (( avail_gb < AVAIL_MIN_GB || use > USE_MAX_PCT )); then
  MSG="Media disk low: ${avail_gb}G free (${use}% used)"
  logger -t disk-alert "$MSG"
  curl -s --max-time 5 -H "Content-Type: application/json" -X POST "$KODI_RPC" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"GUI.ShowNotification\",\"params\":{\"title\":\"Storage Warning\",\"message\":\"${MSG}\",\"displaytime\":15000}}" >/dev/null 2>&1 || true
  exit 0
fi
logger -t disk-alert "OK: ${avail_gb}G free (${use}% used)"
