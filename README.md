# dlbox

Self-hosted home server stack running on an Intel i3-N305 mini PC (Debian 13). Manages smart home automation, media streaming, network management, and 3D printing.

## Stack overview

The root `docker-compose.yml` uses `include:` to pull in four sub-stacks:

| Stack | File | Services |
|---|---|---|
| Top-level | `docker-compose.yml` | Traefik, Watchtower, static portal |
| Home Assistant | `hass/docker-compose.yml` | HA, PostgreSQL, Mosquitto, Zigbee2MQTT, Matter Server, OTBR |
| Streaming | `streaming/docker-compose.yml` | Jellyfin, Sonarr, Radarr, Lidarr, Prowlarr, Flaresolverr, qBittorrent+Gluetun, Calibre-Web |
| Network | `network/docker-compose.yml` | UniFi OS Server |
| 3D Print | `3dprint/docker-compose.yml` | BambuBuddy, Bambu Studio API |

All services that need Traefik join the external `proxy_net` network. Streaming services also share an internal `172.20.0.0/24` bridge (`dlbox0`). The top-level network is `172.21.0.0/24`.

## Hardware requirements

This machine does **not** have built-in Bluetooth or WiFi. The following USB hardware must be plugged in:

| Device | Purpose |
|---|---|
| CH340 USB serial adapter (`usb-1a86_USB_Serial-if00-port0`) | Zigbee coordinator (ZStack) |
| Zigbee Dongle ZBM-MG24 (`usb-Zigbee_Dongle_ZBM-MG24_*`) | OpenThread Border Router RCP |
| USB Bluetooth dongle (any BT 4.0+ adapter) | BLE sensor passthrough |

Intel GPU is required for Jellyfin hardware transcoding: `/dev/dri/card0` and `/dev/dri/renderD128` must exist.

## External dependencies

- **Cloudflare** — domain `iammikhail.com` is managed via Cloudflare. A DNS API token with `Zone:DNS:Edit` is needed for automatic SSL cert renewal via ACME.
- **Private Internet Access VPN** — credentials required for qBittorrent's VPN tunnel (Gluetun).

---

## First-time setup

### 1. Install system packages

```bash
sudo apt-get install -y bluez
```

### 2. Enable bluetoothd with the experimental flag

Home Assistant's passive BLE scanning requires `bluetoothd` to run with `--experimental`. A helper script handles this:

```bash
sudo /home/topfish/.config/dlbox/scripts/fix-bluetooth-experimental.sh
```

This creates a systemd drop-in at `/etc/systemd/system/bluetooth.service.d/experimental.conf` and restarts bluetoothd. It is safe to re-run.

Verify it's active:

```bash
systemctl show bluetooth --property=ExecStart | grep experimental
```

### 3. Create the proxy_net Docker network

This external network is shared across all sub-stacks and must exist before starting:

```bash
docker network create proxy_net
```

### 4. Configure the VLAN interface

Matter Server and OTBR both require `enp2s0.10` to exist on the host for Thread/Matter networking. Create it:

```bash
sudo ip link add link enp2s0 name enp2s0.10 type vlan id 10
sudo ip link set enp2s0.10 up
```

Then apply the IPv6 fix required for OTBR to advertise itself on the network. OMV disables IPv6 link-local by default, which breaks OTBR's `_meshcop._udp` service discovery. Create `/etc/systemd/system/enp2s0.10-ipv6-linklocal.service`:

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

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now enp2s0.10-ipv6-linklocal.service
```

| Setting | Value | Reason |
|---|---|---|
| `addr_gen_mode` | 0 | Generates EUI-64 link-local IPv6 (OMV sets this to 1) |
| `disable_ipv6` toggle | 1→0 | Forces kernel to re-initialise IPv6 and generate the link-local |
| `accept_ra` | 2 | OTBR infra agent needs RAs even with IPv6 forwarding enabled |
| `accept_ra_rt_info_max_plen` | 64 | Allows OTBR to learn /64 prefix routes from upstream router |
| `rp_filter` | 2 (loose) | Prevents kernel dropping packets from other subnets (e.g. WireGuard at 192.168.2.x) |

### 5. Verify serial devices

```bash
ls -la /dev/serial/by-id/
```

Expected output:

```
usb-1a86_USB_Serial-if00-port0                                    → ../../ttyUSB1  (Zigbee)
usb-Zigbee_Dongle_ZBM-MG24_f633ebea3b5ef011af8353401045c30f-if00-port0  → ../../ttyUSB0  (Thread)
```

The ttyUSBx numbers can change across reboots — the `.env` uses stable by-id paths to prevent this. If adapters change, update `ZIGBEE_DEVICE` and `THREAD_DEVICE` in `.env`.

### 6. Prepare config directories

All persistent container data lives under `CONFIG_ROOT` (`/home/topfish/.config/Docker/config`):

```bash
CONFIG_ROOT=/home/topfish/.config/Docker/config
mkdir -p \
  $CONFIG_ROOT/traefik \
  $CONFIG_ROOT/postgres \
  $CONFIG_ROOT/mosquitto/data \
  $CONFIG_ROOT/mosquitto/log \
  $CONFIG_ROOT/matter-server \
  $CONFIG_ROOT/otbr \
  $CONFIG_ROOT/qbittorrent \
  $CONFIG_ROOT/prowlarr \
  $CONFIG_ROOT/sonarr \
  $CONFIG_ROOT/radarr \
  $CONFIG_ROOT/lidarr \
  $CONFIG_ROOT/jellyfin \
  $CONFIG_ROOT/calibre-web \
  $CONFIG_ROOT/bambuddy/data \
  $CONFIG_ROOT/bambuddy/logs \
  $CONFIG_ROOT/bambu-studio-api \
  $CONFIG_ROOT/unifi-os-server/persistent \
  $CONFIG_ROOT/unifi-os-server/var-log \
  $CONFIG_ROOT/unifi-os-server/data \
  $CONFIG_ROOT/unifi-os-server/srv \
  $CONFIG_ROOT/unifi-os-server/var-lib-unifi \
  $CONFIG_ROOT/unifi-os-server/var-lib-mongodb \
  $CONFIG_ROOT/unifi-os-server/etc-rabbitmq-ssl
```

### 7. Initialise Traefik SSL certificate storage

```bash
touch $CONFIG_ROOT/traefik/acme.json
chmod 600 $CONFIG_ROOT/traefik/acme.json
```

Traefik populates this on first run. It must be `chmod 600` or Traefik refuses to start.

### 8. Create the .env file

Copy the template and fill in credentials:

```env
PUID=1003                    # run: id -u
PGID=1000                    # run: id -g
TZ=Australia/Sydney

CONFIG_ROOT=/home/topfish/.config/Docker/config
MEDIA_ROOT=/srv/dev-disk-by-uuid-5aa5da85-1b01-4ef8-bba7-b695eb766e3a/Media
STATIC_ROOT=/home/topfish/.config/dlbox/static

CF_DNS_API_TOKEN=            # Cloudflare API token, Zone:DNS:Edit permission
PIA_USERNAME=                # Private Internet Access username
PIA_PASSWORD=                # Private Internet Access password

# Use stable by-id paths — ttyUSBx numbers shift if adapters are replugged
ZIGBEE_DEVICE=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
THREAD_DEVICE=/dev/serial/by-id/usb-Zigbee_Dongle_ZBM-MG24_f633ebea3b5ef011af8353401045c30f-if00-port0
```

> **Security:** `.env` contains credentials — it is gitignored. Do not commit it.

### 9. Configure DNS

Point all subdomains to this host's public IP via Cloudflare (a wildcard `*.iammikhail.com` record works):

| Domain | Routes to |
|---|---|
| `hass.iammikhail.com` | Home Assistant (port 8123 on host) |
| `downloads.iammikhail.com` | Portal, Jellyfin, qBittorrent, Sonarr, Radarr, Lidarr, Prowlarr |
| `jellyfin.iammikhail.com` | Jellyfin (alternate domain, root redirects to `/jellyfin`) |
| `unifi.iammikhail.com` | UniFi controller |
| `bambuddy.iammikhail.com` | BambuBuddy (port 8000 on host) |
| `nas.iammikhail.com` | NAS at 192.168.10.201:5000 |
| `proxy.nas.iammikhail.com` | Traefik dashboard |

---

## Running the stack

**Always run compose commands from `/home/topfish/.config/dlbox`.** Running from a subdirectory creates a different Docker project name and produces "container name already in use" errors.

```bash
cd /home/topfish/.config/dlbox

# Start everything
docker compose up -d

# Stop everything
docker compose down

# Recreate a single service without touching its dependencies
docker compose up -d --no-deps <service-name>
```

---

## Service notes

### Home Assistant

- Runs on host network (port 8123), proxied through Traefik at `hass.iammikhail.com`.
- Uses PostgreSQL for long-term statistics (not the default SQLite).
- Requires `NET_ADMIN` and `NET_RAW` capabilities and `/dev/rfkill` for Bluetooth management.
- D-Bus is mounted read-write (`/run/dbus:/run/dbus`) so bluetoothd can manage the BT adapter.

### Bluetooth / BLE sensors

- This machine has no built-in Bluetooth — a USB dongle is required.
- `bluetoothd` must be running with `--experimental` (see setup step 2).
- BLE temperature sensors are managed by the `ble_monitor` custom HACS integration.
- If BLE sensors go unavailable: verify the dongle is present (`ls /sys/class/bluetooth/`), bluetoothd is active with `--experimental`, and ble_monitor has the adapter selected (not "disable") under Settings → Integrations → BLE Monitor → Configure.

### Zigbee2MQTT

- Uses the CH340 USB serial adapter, `adapter: zstack`, configured in `hass/zigbee2mqtt/configuration.yaml`.
- `ZIGBEE_DEVICE` in `.env` maps the host by-id path to `/dev/ttyUSB0` inside the container.
- If devices stop responding after a reboot, verify the by-id path still resolves: `ls /dev/serial/by-id/`.

### OpenThread Border Router (OTBR)

- Uses the ZBM-MG24 adapter at 460800 baud (hardcoded in firmware; 115200 fails).
- `OT_RCP_DEVICE` is hardcoded to `spinel+hdlc+uart:///dev/ttyUSB0` — the in-container path. The host device is controlled only by `THREAD_DEVICE` in `.env` via the `devices:` mapping. Do not change `OT_RCP_DEVICE` to a host by-id path.
- Thread network state persists in `$CONFIG_ROOT/otbr`. Losing this directory means all Thread devices must be recommissioned.
- REST API at `http://localhost:8087`, web UI at `http://localhost:8086`.

**OTBR crash loop fix** — if `docker logs otbr` shows repeated `RadioSpinelNoResponse` or `Unexpected RCP reset RESET_UNKNOWN` errors, the stored dataset is stale. Reset it:

```bash
docker stop otbr
sudo rm -rf $CONFIG_ROOT/otbr/*
docker start otbr
```

### Thread devices (Matter over Thread)

- Battery-powered Thread buttons (e.g. IKEA BILRESA) are **sleepy end devices**. They disconnect when idle and only wake on button press.
- If a Thread device shows unavailable in HA after OTBR restarts, press a button on the device to trigger it to rejoin.
- If pressing produces no response and the device doesn't appear in `docker exec otbr ot-ctl child table`, check the battery — dead batteries are completely silent on the radio.

### Matter Server

- Requires `enp2s0.10` to exist on the host (see setup step 4).
- Commissioned device data lives in `$CONFIG_ROOT/matter-server/`. Losing this directory requires recommissioning all Matter devices.

### Jellyfin

- Hardware transcoding via Intel GPU. Devices `/dev/dri/card0` and `/dev/dri/renderD128` must exist. Update paths in `streaming/docker-compose.yml` for AMD/NVIDIA.
- Available at `downloads.iammikhail.com/jellyfin` and `jellyfin.iammikhail.com/jellyfin`.

### qBittorrent + Gluetun VPN

- qBittorrent runs inside Gluetun's network namespace — all traffic routes through PIA VPN (Singapore region).
- If Gluetun is unhealthy, qBittorrent loses all network access. Check VPN credentials if it fails to start.
- WebUI at `downloads.iammikhail.com/qbit`.

### UniFi OS Server

- Full UniFi OS in a container — includes MongoDB, RabbitMQ, and the complete controller stack.
- Accessible at `https://unifi.iammikhail.com` (proxied from internal port 11443 with `insecureSkipVerify`).
- Requires `/sys/fs/cgroup` mounted read-write.

### Watchtower

- Automatically updates all containers daily at 03:00 UTC.
- The `static-host` container is excluded from automatic updates.

---

## Troubleshooting

### "container name already in use"

You ran compose from the wrong directory. Always run from `/home/topfish/.config/dlbox`.

### Zigbee or Thread stops working after reboot

`ttyUSBx` numbers can shift. Verify by-id paths still resolve:

```bash
ls -la /dev/serial/by-id/
```

Recreate affected containers to apply any `.env` changes:

```bash
docker compose up -d --no-deps zigbee2mqtt otbr
```

### BLE sensors unavailable

1. Check dongle is present: `ls /sys/class/bluetooth/`
2. Check bluetoothd is running with `--experimental`: `systemctl status bluetooth`
3. In HA: Settings → Integrations → BLE Monitor → Configure → verify an adapter is selected, not "disable"

### Thread device unavailable

1. Press a button on the device to wake it
2. Check it appears: `docker exec otbr ot-ctl child table`
3. If still absent, check the battery

### OTBR fails to start — "No such file or directory"

`OT_RCP_DEVICE` contains a host path that doesn't exist inside the container. Confirm `hass/docker-compose.yml` has:

```yaml
- OT_RCP_DEVICE=spinel+hdlc+uart:///dev/ttyUSB0?uart-baudrate=460800
```

### Traefik not issuing SSL certificates

- Verify `CF_DNS_API_TOKEN` is set and has `Zone:DNS:Edit` permission
- Verify `acme.json` exists and is `chmod 600`
- Check logs: `docker logs traefik`

### HA bluetooth error "org.bluez not provided by any .service files"

`bluetoothd` is not running. Start it and verify the experimental flag is set:

```bash
sudo systemctl start bluetooth
systemctl show bluetooth --property=ExecStart | grep experimental
```

If the flag is missing, re-run `sudo scripts/fix-bluetooth-experimental.sh`.

---

## Directory structure

```
dlbox/
├── docker-compose.yml               # Root — includes all sub-stacks
├── .env                             # Credentials and paths (gitignored)
├── traefik/
│   ├── traefik.yml                  # Static Traefik config
│   └── dynamic.yml                  # File-based routes (HA, BambuBuddy, NAS)
├── hass/
│   ├── docker-compose.yml           # HA, PostgreSQL, Mosquitto, Z2M, Matter, OTBR
│   ├── config/                      # Home Assistant configuration files
│   ├── zigbee2mqtt/                 # Zigbee2MQTT config and device database
│   └── mosquitto/                   # Mosquitto broker config
├── streaming/
│   └── docker-compose.yml           # Jellyfin, *arr stack, qBittorrent, Gluetun
├── network/
│   └── docker-compose.yml           # UniFi OS Server
├── 3dprint/
│   └── docker-compose.yml           # BambuBuddy, Bambu Studio API
├── static/                          # Portal landing page assets
└── scripts/
    └── fix-bluetooth-experimental.sh  # Enables --experimental on bluetoothd
```
