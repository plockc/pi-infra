#!/bin/bash
# created by README-build-node.md
set -euo pipefail

if [[ "" != "" ]]; then
    sudo cp wlan0.yaml /etc/netplan/
fi
sudo cp eth0.yaml /etc/netplan/
sudo rm -f /etc/netplan/99-cloud-init.yaml
sudo cp hostname /etc/
