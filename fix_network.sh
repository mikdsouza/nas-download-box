#!/bin/bash

if ! ping -c2 192.168.0.1 > /dev/null; then
	sudo reboot now
fi

