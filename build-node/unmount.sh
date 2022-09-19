#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh

sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

echo Completed!
