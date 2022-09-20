#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail

PIROOT=/media/$USER/piroot

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/cloud-init-ssh-authorized-keys.cfg 99-ssh-authorized-keys.cfg
sudo cp ~1/cloud-init-disable-network-config.cfg 99-disable-network-config.cfg
sudo cp ~1/cloud-init-gw-hostname.cfg 99-hostname.cfg
popd

pushd "$PIROOT"/etc
if [[ "" != "" ]]; then
    sudo cp wlan0.yaml netplan/
fi
sudo cp ~1/eth0.yaml netplan/
sudo cp ~1/resolved.conf systemd/
popd
