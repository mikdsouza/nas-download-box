NAS Download Box
================

I'm assuming here that you're pulling into `~/.config/dlbox/`

## If running in a VM

Fix the hosts file. Edit `sudo vim /etc/hosts` and add the hostname to the end of the first line

Update the VM packages

```
$ sudo apt install curl wget apt-transport-https dirmngr git
$ sudo apt update -y && sudo apt upgrade -y
```

Also fix the perms and the ssh keys
```
$ sudo chown admin ~
$ sudo chown admin ~/.*
$ ssh-keygen -t rsa
```

Transfer your ssh key with

```
ssh-copy-id admin@192.168.0.162
```

Fix the legacy iptables thing

```
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
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

Alternatively, set up a consistent mac address instead by editing `/volume1/.@plugins/AppCentral/linux-center/containers/debian10-server/net` to add

```
lxc.network.hwaddr=da:35:dc:8b:ab:66
```

Now this part is fucking dumb but for whatever reason, the eth0 interface stops working after a suspend. Only way to fix it seems to be to reboot it.
There is a script called `fix_network.sh` which does a ping to the router at `192.168.0.1` and calls reboot if that doesn't work.

To setup this cronjob, first allow the user to reboot without the need for `sudo`. Add this to the sudo file with `sudo visudo`

```
# Admin user group
%admin  ALL=NOPASSWD: /sbin/halt, /sbin/reboot, /sbin/poweroff
```

Then add the following cronjob `sudo crontab -u admin -e`

```
* * * * * /home/admin/.config/dlbox/fix_network.sh
```

If it all goes to shit and now you can't access the container because it keeps restarting, you can always edit the FS directly at

```
/volume1/.@plugins/AppCentral/linux-center/containers/debian10-server/rootfs/home/admin
```

Finally, get everything going with

```
docker-compose up -d
```

This should come up at start up if docker is configured to start at startup.

Fix some file permissions with

```
sudo chown -R admin:docker ~/share
```

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
