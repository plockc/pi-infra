#!/bin/bash
# created by README-build-node.md
set -euo pipefail

PIROOT=/media/$USER/piroot

pushd "$PIROOT"/etc/netplan
sudo cp ~1/{wlan0,eth{0,1}}.yaml .
popd
