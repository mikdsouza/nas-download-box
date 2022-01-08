NAS Download Box
================

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