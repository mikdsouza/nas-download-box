NAS Download Box
================

Assuming you're cloning into `~/.config/dlbox/`.

## Configuration

Copy or create the `.env` file in the repo root:

```
PUID=1003
PGID=1000
TZ=Australia/Sydney
CONFIG_ROOT=/home/topfish/.config/Docker/config
MEDIA_ROOT=/srv/dev-disk-by-uuid-.../Media
NGINX_ROOT=/home/topfish/.config/dlbox/nginx
STATIC_ROOT=/home/topfish/.config/dlbox/static
CF_DNS_API_TOKEN=<your Cloudflare API token>
```

`PUID`/`PGID` can be found by running `id <user>`.

The Cloudflare API token needs **Zone:DNS:Edit** permissions for `iammikhail.com`.

## First-time setup

Create the Traefik config directory (needs to be done once manually due to permissions):

```
sudo mkdir -p $CONFIG_ROOT/traefik
sudo chown $USER:$USER $CONFIG_ROOT/traefik
```

Then run the setup script, which creates the Docker network, initialises `acme.json`, and starts all stacks:

```
./setup.sh
```

## Stacks

The compose setup is split into three stacks, all managed from the root `docker-compose.yml` via `include`:

| Stack | File | Services |
|-------|------|----------|
| Top-level | `docker-compose.yml` | Traefik, Watchtower, static site |
| Streaming | `streaming/docker-compose.yml` | Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent, Jellyfin, Calibre-Web, FlareSolverr |
| Network | `network/docker-compose.yml` | UniFi OS Server |

All services that need to be reachable by Traefik join the external `proxy_net` network. The streaming stack also uses an internal `172.20.0.0/24` bridge (`dlbox0`).

## Proxy / Traefik

Traefik handles all inbound traffic on ports 80 and 443. HTTP is redirected to HTTPS automatically. TLS certificates are issued via Let's Encrypt using the Cloudflare DNS challenge.

| Domain | Routes to |
|--------|-----------|
| `downloads.iammikhail.com` | Static site (root), Jellyfin (`/jellyfin`), qBittorrent (`/qbit`), Sonarr (`/sonarr`), Radarr (`/radarr`), Lidarr (`/lidarr`), Prowlarr (`/prowlarr`) |
| `unifi.iammikhail.com` | UniFi OS Server |
| `nas.iammikhail.com` | NAS at `192.168.10.201:5000` |
| `proxy.nas.iammikhail.com` | Traefik dashboard |

Traefik config lives in `traefik/` (tracked in git). The `acme.json` cert store lives at `$CONFIG_ROOT/traefik/acme.json` (not in git).

## Running the stack

Start everything:

```
./setup.sh
```

Or directly:

```
docker compose up -d
```

Stop everything:

```
docker compose down
```
