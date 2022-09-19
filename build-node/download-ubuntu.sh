#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh
FILE=ubuntu-${UBUNTU_VERSION}.${UBUNTU_PATCH_VERSION}-preinstalled-desktop-arm64+raspi.img.xz
if [ ! -e $FILE ]; then
    wget --no-clobber http://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release/$FILE
fi
