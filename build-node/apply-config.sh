#!/bin/bash
# created by README-build-node.md
set -euo pipefail

if [[ "" != "" ]]; then
    sudo cp build-node/wlan0.yaml /etc/netplan/
fi
sudo cp build-node/{eth{0,1}}.yaml /etc/netplan/
sudo rm /etc/netplan/99-cloud-init.yaml
sudo cp build-node/hostname /etc/
