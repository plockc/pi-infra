#!/bin/bash
# created by README-build-node.md
set -euo pipefail

PIROOT=/media/$USER/piroot

pushd "$PIROOT"/etc/netplan
sudo cp ~1/build-node/{wlan0,eth{0,1}}.yaml .
popd

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/build-node/cloud-init-disable-network-config.cfg 99-disable-network-config.cfg
sudo cp ~1/build-node/ssh_authorized_keys.cfg 99-ssh_authorized_keys.cfg
sudo cp ~1/build-node/cloud-init-packages.cfg 99-packages.cfg
popd

pushd $PIROOT/etc
sudo cp ~1/build-node/resolved.conf systemd/resolved.conf
sudo cp ~1/build-node/cloud-init-hostname.cfg cloud/cloud.cfg.d/99-hostname.cfg
sudo mkdir -p iptables
sudo cp ~1/build-node/rules.v4 iptables/
popd

pushd "$PIROOT"/etc/sysctl.d
sudo cp ~1/build-node/forwarding.conf 99-forwarding.conf
popd

mkdir /var/cache/images
sudo cp build-node/*raspi.img.xz "$PIROOT"/var/cache/images/
