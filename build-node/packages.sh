#!/bin/bash
# created by README-build-node.md
set -e
sudo apt install -y \
  silversearcher-ag make gcc rng-tools jq pv
sudo snap install --classic nvim
sudo snap install --classic go
