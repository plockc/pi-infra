#!/bin/bash
# created by README-gateway.md
set -euo pipefail

pushd /etc
sudo mkdir -p systemd/resolved.conf.d
sudo cp ~1/disable-stub-listener.conf systemd/resolved.conf.d
sudo cp ~1/dnsmasq-pocket.conf dnsmasq.d/pocket
sudo cp ~1/dnsmasq-hosts hosts.dnsmasq
sudo cp ~1/dnsmasq-resolv.conf resolv.dnsmasq.conf
popd

# will stop hostname resolution
sudo systemctl restart systemd-resolved
# will restore hostname resolution
sudo systemctl restart dnsmasq
# fix local host name resolution
# first remove the symlink to systemd/resolve/stub-resolv.conf
sudo rm /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf > /dev/null
