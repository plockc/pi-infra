#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. install-vars.sh

PIROOT=/media/$USER/piroot
sudo mkdir -p /media/$USER/piboot "$PIROOT"
sudo mount /dev/${DEVICE}1 /media/$USER/piboot
sudo mount /dev/${DEVICE}2 "$PIROOT"
