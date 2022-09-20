#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail

PIROOT=/media/$USER/piroot
sudo mkdir -p /media/$USER/piboot "$PIROOT"
sudo mount /dev/sda1 /media/$USER/piboot
sudo mount /dev/sda2 "$PIROOT"
