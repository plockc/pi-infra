#!/bin/bash
# created by README-build-node.md
set -e
sudo apt install -y \
  python3-pip silversearcher-ag make gcc rng-tools jq pv autoconf bison gperf autopoint texinfo
sudo snap install --classic nvim
sudo snap install --classic go
