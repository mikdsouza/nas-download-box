NAS Download Box
================

I'm assuming here that you're pulling into `~/.config/dlbox/`

## If running in a VM

Update the VM packages

```
$ sudo apt update -y && sudo apt upgrade -y
```

Restart. Then install docker following [https://docs.docker.com/engine/install/debian/].
Also follow the instructions to set up the non-root docker usage.

Then install docker compose

```
$ sudo apt install docker-compose
```

Also set up a static IP by adding this to `/etc/network/interfaces`

```
auto eth0
iface eth0 inet static
    address 192.168.0.162
    gateway 192.168.0.1
    netmask 255.255.255.0
    dns-search debian10test
    dns-nameservers 192.168.0.233 8.8.4.4
```

Finally, get everything going with

```
docker-compose up -d
```

This should come up at start up if docker is configured to start at startup.

## If running directly on the NAS

Install `docker-ce` from the store. Do not install Portainer, I can never get it to work properly.

Edit the docker startup script at `/volume1/.@plugins/AppCentral/docker-ce/CONTROL/start-stop.sh`

```
# Located in /volume1/.@plugins/AppCentral/docker-ce/CONTROL/start-stop.sh
# Add this under the "start" instructions

echo "Kill myhttp to so nginx can take it over"
/usr/bin/pkill /usr/sbin/myhttpd
```

The modify your .env file with

```
PUID=1003
PGID=1000
TZ=Australia/Sydney
CONFIG_ROOT=/volume1/Docker/config
MEDIA_ROOT=/volume1/Media
NGINX_ROOT=/home/topfish/.config/dlbox/nginx
```

To figure out the PID, run `id deamon`
