#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. vars.sh

PIROOT=/media/$USER/piroot

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/cloud-init-ssh.cfg 99-ssh.cfg
sudo cp ~1/cloud-init-disable-network-config.cfg 99-disable-network-config.cfg
sudo cp ~1/cloud-init-hostname.cfg 99-hostname.cfg
popd

pushd "$PIROOT"/etc
if [[ "${WIFI_SSID:-}" != "" ]]; then
    sudo cp sd-card-wlan0.yaml /etc/netplan/
fi
sudo cp ~1/sd-card-eth0.yaml netplan/
popd
