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

## Home Assistant / Thread / Matter

The `hass/` stack runs Home Assistant, Zigbee2MQTT, OTBR (OpenThread Border Router), and Matter Server.

### .env

The `hass/.env` file must contain stable by-id device paths to avoid USB ordering issues on reboot:

```
TZ=Australia/Sydney
CONFIG_ROOT=/home/topfish/.config/Docker/config
ZIGBEE_DEVICE=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
THREAD_DEVICE=/dev/serial/by-id/usb-Zigbee_Dongle_ZBM-MG24_f633ebea3b5ef011af8353401045c30f-if00-port0
OTBR_BACKBONE_IF=enp2s0.10
```

### Host networking setup (required once per machine)

OMV manages `enp2s0.10` via netplan and disables IPv6 link-local by default (`link-local: []`). OTBR requires a link-local IPv6 address on its backbone interface to advertise `_meshcop._udp` (how HA discovers the border router). The following systemd service corrects this after networkd runs on every boot.

**Create `/etc/systemd/system/enp2s0.10-ipv6-linklocal.service`:**

```ini
[Unit]
Description=OTBR host networking for enp2s0.10 (accept_ra=2, loose rp_filter)
After=sys-subsystem-net-devices-enp2s0.10.device systemd-networkd.service
Wants=sys-subsystem-net-devices-enp2s0.10.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
  echo 0 > /proc/sys/net/ipv6/conf/enp2s0.10/addr_gen_mode && \
  echo 1 > /proc/sys/net/ipv6/conf/enp2s0.10/disable_ipv6 && \
  echo 0 > /proc/sys/net/ipv6/conf/enp2s0.10/disable_ipv6 && \
  echo 2 > /proc/sys/net/ipv6/conf/enp2s0.10/accept_ra && \
  echo 64 > /proc/sys/net/ipv6/conf/enp2s0.10/accept_ra_rt_info_max_plen && \
  echo 2 > /proc/sys/net/ipv4/conf/enp2s0.10/rp_filter'

[Install]
WantedBy=multi-user.target
```

Then enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now enp2s0.10-ipv6-linklocal.service
```

**What each setting does:**

| Setting | Value | Reason |
|---------|-------|--------|
| `addr_gen_mode` | 0 | generates EUI-64 link-local IPv6 (OMV sets this to 1/disabled) |
| `disable_ipv6` toggle | 1→0 | forces kernel to re-initialise IPv6 and generate the link-local |
| `accept_ra` | 2 | OTBR infra agent needs router advertisements even with IPv6 forwarding on |
| `accept_ra_rt_info_max_plen` | 64 | allows OTBR to learn /64 prefix routes from the upstream router |
| `rp_filter` | 2 (loose) | prevents kernel dropping inbound packets from other subnets (e.g. WireGuard VPN at 192.168.2.x) |

### OTBR crash loop

If `docker logs otbr` shows repeated `RadioSpinelNoResponse` / `Unexpected RCP reset RESET_UNKNOWN` errors at `MAC_15_4_SADDR saddr:0x5c00`, the stored Thread dataset is stale. Fix:

```bash
docker stop otbr
sudo rm -rf $CONFIG_ROOT/otbr/*
docker start otbr
```

### Thread dongle

The Sonoff ZBM-MG24 runs `SL-OPENTHREAD/2.4.4.0` at **460800 baud** (hardcoded in firmware — 115200 fails). The `THREAD_DEVICE` env var must point to its by-id path.

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
