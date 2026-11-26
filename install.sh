#!/usr/bin/env bash
# iMac9,1 Media Center — full installer / orchestrator.
#
# Turns a 2009 iMac (iMac9,1, GeForce 9400M) running Ubuntu into a Kodi
# appliance + Jellyfin/Jellyseerr/Homepage streaming stack with a full
# Sonarr/Radarr/Prowlarr/Transmission download pipeline.
#
# Usage:
#   ./install.sh                 # show the phase menu
#   sudo ./install.sh all        # run every phase in order (stops at the reboot gate)
#   sudo ./install.sh deps firmware kodi arrs jellyfin dashboard addon alert
#   ./install.sh status          # what is installed / running
#
# It is idempotent: re-running a phase is safe. Read docs/ before the first run —
# the hardware-decode phase needs a reboot in the middle. See README.md.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_USER="${MEDIA_USER:-$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")}"
MEDIA_ROOT="${MEDIA_ROOT:-/srv/media}"
IP="$(hostname -I | awk '{print $1}')"

c()   { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
warn(){ printf '\033[1;33m  ! %s\033[0m\n' "$*" >&2; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }
need_root(){ [ "$(id -u)" -eq 0 ] || die "this phase needs sudo"; }

preflight() {
    c "Preflight"
    . /etc/os-release 2>/dev/null || true
    grep -q sse4_1 /proc/cpuinfo || warn "no SSE4.1 — wrong CPU? expected Core 2 Duo"
    if grep -q sse4_2 /proc/cpuinfo; then
        warn "this CPU has SSE4.2 — you may not be on an iMac9,1; the codec limits may not apply"
    fi
    ok "user=$MEDIA_USER  media=$MEDIA_ROOT  ip=$IP  os=${PRETTY_NAME:-unknown}"
}

phase_deps() {
    need_root; c "Phase: base packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg jq rsync samba \
        kodi mpv vainfo mesa-va-drivers \
        transmission-daemon sqlite3 || die "apt install failed"
    install -d -m 0755 "$MEDIA_ROOT"/{Movies,TV,Music,Pictures} /srv/downloads/{complete,incomplete}
    chown -R "$MEDIA_USER":"$MEDIA_USER" "$MEDIA_ROOT" /srv/downloads
    ok "base packages + media tree ready"
}

phase_firmware() {
    need_root; c "Phase: VP3 hardware-decode firmware"
    "$HERE/scripts/install-firmware.sh" "${DRIVER_RUN:-}" || die "firmware step failed"
    install -D -m 0644 "$HERE/config/playercorefactory.xml" \
        "/home/$MEDIA_USER/.kodi/userdata/playercorefactory.xml"
    chown -R "$MEDIA_USER":"$MEDIA_USER" "/home/$MEDIA_USER/.kodi" 2>/dev/null || true
    install -m 0755 "$HERE/scripts/hwdecode" /usr/local/bin/hwdecode
    warn "REBOOT REQUIRED now (microcode + GPU clock). Then: sudo ./install.sh kodi arrs jellyfin dashboard addon alert"
}

phase_kodi() {
    need_root; c "Phase: Kodi shell (sddm autologin, no desktop)"
    apt-get install -y --no-install-recommends sddm || die "sddm install failed"
    install -D -m 0644 "$HERE/config/sddm.conf.example" /etc/sddm.conf.d/autologin.conf
    sed -i "s/^User=.*/User=$MEDIA_USER/" /etc/sddm.conf.d/autologin.conf 2>/dev/null || true
    systemctl set-default graphical.target
    systemctl enable sddm
    ok "Kodi set as the on-screen shell (reboot or restart sddm to enter it)"
    warn "verify hw decode first:  vainfo 2>&1 | grep -i h264  — see docs/HARDWARE-DECODE.md"
}

phase_arrs() {
    need_root; c "Phase: Sonarr/Radarr/Prowlarr + Transmission"
    # Transmission: disable RPC auth for LAN, point at /srv/downloads
    systemctl stop transmission-daemon 2>/dev/null || true
    local tj="/var/lib/transmission-daemon/.config/transmission-daemon/settings.json"
    if [ -f "$tj" ]; then
        jq '."rpc-authentication-required"=false | ."rpc-whitelist-enabled"=false |
            ."download-dir"="/srv/downloads/complete" |
            ."incomplete-dir"="/srv/downloads/incomplete" | ."incomplete-dir-enabled"=true' \
            "$tj" > "$tj.new" && mv "$tj.new" "$tj" && chown debian-transmission: "$tj"
    fi
    systemctl start transmission-daemon 2>/dev/null || true
    # Servarr apps via the official installer (idempotent per app)
    for app in sonarr radarr prowlarr; do
        if ! systemctl list-unit-files | grep -q "^$app"; then
            c "installing $app (Servarr)"
            curl -fsSL "https://raw.githubusercontent.com/Servarr/Wiki/master/servarr/servarr-install-script.sh" \
                -o /tmp/servarr.sh && bash /tmp/servarr.sh --app "$app" --installdir /opt --branch master \
                --user "$MEDIA_USER" --group "$MEDIA_USER" </dev/null || warn "$app install needs manual run — see docs/ARR-STACK.md"
        fi
    done
    # Disable auth on LAN for each arr
    for conf in /var/lib/sonarr/config.xml /var/lib/radarr/config.xml /var/lib/prowlarr/config.xml; do
        [ -f "$conf" ] && sed -i \
          's#<AuthenticationRequired>[^<]*</AuthenticationRequired>#<AuthenticationRequired>DisabledForLocalAddresses</AuthenticationRequired>#' "$conf"
    done
    systemctl restart sonarr radarr prowlarr 2>/dev/null || true
    ok "download stack up. Configure codec filters per docs/ARR-STACK.md (no HEVC/VP9/AV1)"
}

phase_jellyfin() {
    need_root; c "Phase: Jellyfin (pinned 10.11.11 — direct play only)"
    if ! command -v jellyfin >/dev/null; then
        curl -fsSL https://repo.jellyfin.org/install-debuntu.sh | bash || die "jellyfin install failed"
    fi
    # Pin to 10.11.11 so the Homepage widget keeps working (12.x dropped /emby + api_key query)
    apt-get install -y --allow-downgrades jellyfin-server=10.11.11 jellyfin-web=10.11.11 2>/dev/null || \
        warn "could not pin 10.11.11 exactly — check: apt-cache madison jellyfin-server"
    apt-mark hold jellyfin jellyfin-server jellyfin-web 2>/dev/null || true
    systemctl enable --now jellyfin
    ok "Jellyfin on :8096 — add libraries Movies ($MEDIA_ROOT/Movies) + TV Shows ($MEDIA_ROOT/TV)"
    warn "point it at $MEDIA_ROOT; see docs/STREAMING-PIPELINE.md for the passwordless-LAN setup"
}

phase_dashboard() {
    need_root; c "Phase: Docker + Homepage + Jellyseerr"
    command -v docker >/dev/null || { apt-get install -y docker.io && systemctl enable --now docker; }
    install -d -m 0755 /srv/homepage/config /srv/jellyseerr/config
    # seed Homepage config from the repo if not already present
    for f in settings.yaml; do
        [ -f "/srv/homepage/config/$f" ] || install -m 0644 "$HERE/config/homepage/$f" "/srv/homepage/config/$f"
    done
    [ -f /srv/homepage/config/services.yaml ] || \
        install -m 0644 "$HERE/config/homepage/services.yaml.example" /srv/homepage/config/services.yaml
    docker rm -f homepage jellyseerr 2>/dev/null || true
    docker run -d --name homepage --restart unless-stopped --network host -e PORT=7575 \
        -e HOMEPAGE_ALLOWED_HOSTS="*" -v /srv/homepage/config:/app/config \
        ghcr.io/gethomepage/homepage:latest
    docker run -d --name jellyseerr --restart unless-stopped --network host \
        -v /srv/jellyseerr/config:/app/config fallenbagel/jellyseerr:latest
    ok "Homepage http://$IP:7575  ·  Jellyseerr http://$IP:5055"
    warn "edit /srv/homepage/config/services.yaml and fill in the real API keys (they are REDACTED in the example)"
}

phase_addon() {
    c "Phase: Find Media Kodi add-on"
    sudo -u "$MEDIA_USER" bash "$HERE/scripts/install-addon.sh" || warn "run scripts/install-addon.sh as $MEDIA_USER"
    ok "add-on installed — set Sonarr/Radarr URLs + keys in its settings"
}

phase_alert() {
    need_root; c "Phase: disk-space alert"
    install -m 0755 "$HERE/scripts/disk-alert.sh" /usr/local/bin/disk-alert.sh
    install -m 0644 "$HERE/config/systemd/disk-alert.service" /etc/systemd/system/
    install -m 0644 "$HERE/config/systemd/disk-alert.timer"   /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now disk-alert.timer
    ok "hourly low-disk alert enabled (Kodi on-screen + syslog). journalctl -t disk-alert"
}

phase_status() {
    c "Status"
    for s in sddm jellyfin sonarr radarr prowlarr transmission-daemon disk-alert.timer; do
        printf '  %-22s %s\n' "$s" "$(systemctl is-active "$s" 2>/dev/null || echo -)"
    done
    command -v docker >/dev/null && docker ps --format '  {{.Names}}\t{{.Status}}' 2>/dev/null
    echo "  firmware: $(ls /lib/firmware/nouveau/ 2>/dev/null | grep -c . ) files"
    vainfo 2>/dev/null | grep -qi h264 && ok "VAAPI H264 decode present" || warn "VAAPI H264 not confirmed — see docs/HARDWARE-DECODE.md"
}

menu() {
    cat <<EOF
iMac9,1 Media Center installer

  sudo ./install.sh all          run every phase (stops at the reboot gate)
  ./install.sh status            show what's installed/running

  individual phases (run as sudo unless noted):
    deps        base packages (kodi, mpv, transmission, samba)
    firmware    extract+install VP3 microcode  (REBOOT after)
    kodi        Kodi as the on-screen shell (sddm autologin)
    arrs        Sonarr/Radarr/Prowlarr + Transmission
    jellyfin    Jellyfin media server (pinned 10.11.11)
    dashboard   Docker + Homepage + Jellyseerr
    addon       "Find Media" Kodi add-on  (runs as $MEDIA_USER)
    alert       hourly disk-space alert

Read README.md and docs/ first. The firmware phase needs a reboot before 'kodi'.
EOF
}

run_all() {
    preflight; phase_deps; phase_firmware
    warn "STOP: reboot now, then run:  sudo ./install.sh kodi arrs jellyfin dashboard addon alert"
}

[ $# -eq 0 ] && { menu; exit 0; }
for arg in "$@"; do
    case "$arg" in
        all)       run_all ;;
        preflight) preflight ;;
        deps)      phase_deps ;;
        firmware)  phase_firmware ;;
        kodi)      phase_kodi ;;
        arrs)      phase_arrs ;;
        jellyfin)  phase_jellyfin ;;
        dashboard) phase_dashboard ;;
        addon)     phase_addon ;;
        alert)     phase_alert ;;
        status)    phase_status ;;
        *) die "unknown phase: $arg (run ./install.sh for the menu)" ;;
    esac
done
