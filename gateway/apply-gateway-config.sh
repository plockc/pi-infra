#!/bin/bash
# created by README-gateway.md
set -euo pipefail

sudo hostname gw
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-enabled-fowarding.conf > /dev/null
pushd /etc
sudo cp ~1/eth0.yaml ~1/eth1.yaml netplan/
sudo cp ~1/hostname hostname
sudo mkdir -p iptables
sudo cp ~1/rules.v4 iptables/
popd
