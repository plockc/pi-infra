#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh

xzcat --stdout ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz | pv | sudo dd of=/dev/$DEVICE bs=1M
sudo partprobe
