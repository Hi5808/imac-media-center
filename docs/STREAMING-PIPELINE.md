# Streaming pipeline (Jellyfin + Jellyseerr + Homepage)

The Kodi shell plays media *on the iMac screen*. This layer serves the same
`/srv/media` library to phones, tablets and other devices, adds a self-service
request portal, and puts one dashboard over everything.

Everything here is **direct-play only**. This CPU (Core 2 Duo P7550, SSE4.1
ceiling) cannot transcode video, so the library must already be H.264 / AAC /
SRT — the same constraint the *arr stack enforces (see [ARR-STACK.md](ARR-STACK.md)).

## Components

| Service | Port | How it runs | Purpose |
|---|---|---|---|
| Jellyfin | 8096 | apt package, **pinned 10.11.11** (held) | Media server → phones/devices |
| Homepage | 7575 | Docker, host network | Single dashboard, live widgets |
| Jellyseerr | 5055 | Docker, host network | Request portal (users ask for titles) |

### Why Jellyfin is version-pinned

Jellyfin 12.x dropped the `/emby` alias and `api_key` query auth that the
Homepage widget relies on, which broke the dashboard tile. 10.11.11 is the last
release the widget speaks to cleanly. The package is `apt-mark hold` so the
metapackage cannot jump back to 12.

### Docker + host networking gotcha

Both containers run `--network host`. Under host networking a published port
map (`-p 7575:3000`) is **ignored** — you must tell the app its port directly:

    docker run -d --name homepage --network host -e PORT=7575 \
      -v /srv/homepage/config:/app/config ghcr.io/gethomepage/homepage:latest

    docker run -d --name jellyseerr --network host \
      -v /srv/jellyseerr/config:/app/config fallenbagel/jellyseerr:latest

## Authentication model (LAN appliance, no login friction)

All service UIs are reachable on the LAN without a login prompt:

- **Jellyfin**: user `mac`, blank password (shown on the login screen —
  `IsHidden=false` on the user policy).
- **Sonarr / Radarr / Prowlarr**: `AuthenticationRequired =
  DisabledForLocalAddresses` in each `config.xml`.
- **Transmission**: `rpc-authentication-required: false`.
- **Jellyseerr**: signs in via Jellyfin (same `mac` / blank).

## Request flow

    Jellyseerr (user requests)  ->  Sonarr / Radarr  ->  Prowlarr (indexers)
         ->  Transmission (download)  ->  /srv/media  ->  Jellyfin + Kodi

Jellyseerr is wired to Sonarr (root `/srv/media/TV`) and Radarr
(root `/srv/media/Movies`) as default servers, profile "HD - 720p/1080p",
is4k=false. It reads the Jellyfin libraries (Movies, TV Shows) for "already
available" status.

## Dashboard layout

`config/homepage/settings.yaml` controls **group order** (not services.yaml):
Media -> Requests -> Management -> Downloads. Each group lists live widgets that
poll `http://127.0.0.1:<port>`; the clickable `href` points at the LAN IP.

Real config lives at `/srv/homepage/config/`. The committed
`services.yaml.example` has every API key/password redacted — fill them from
each app before use.

## Disk-space alert

`scripts/disk-alert.sh` (run hourly by `config/systemd/disk-alert.timer`) warns
when `/` drops below 15 G free or above 90% used: it logs to syslog
(`journalctl -t disk-alert`) and pops an on-screen Kodi notification via
JSON-RPC. The media library shares the root disk, so a full disk would crash the
box — this is the early warning.

Install:

    sudo install -m755 scripts/disk-alert.sh /usr/local/bin/disk-alert.sh
    sudo cp config/systemd/disk-alert.* /etc/systemd/system/
    sudo systemctl enable --now disk-alert.timer
