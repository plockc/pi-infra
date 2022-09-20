#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh

sync
sudo umount /dev/sda1 /dev/sda2
sudo eject /dev/sda

echo Completed!
