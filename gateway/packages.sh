#!/bin/bash
# created by README-gateway.md
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo apt install -y rng-tools iptables-persistent netfilter-persistent net-tools prips dnsmasq
