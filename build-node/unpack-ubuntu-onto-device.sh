#!/bin/bash
# created by README-build-node.md
set -euo pipefail
xzcat --stdout ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz | pv | sudo dd of=/dev/$DEVICE bs=1M
sudo partprobe
