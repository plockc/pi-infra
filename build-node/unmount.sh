#!/bin/bash
# created by README-build-node.md
set -euo pipefail
sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

echo Completed!
