#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail

. vars.sh
FILE=ubuntu-${UBUNTU_VERSION}.${UBUNTU_PATCH_VERSION}-preinstalled-server-arm64+raspi.img.xz
xzcat --stdout $FILE | pv | sudo dd of=/dev/sda bs=1M
sudo partprobe
