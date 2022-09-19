#!/bin/bash
# created by README-build-node.md
set -euo pipefail
cd build-node
. upgrade.sh
. packages.sh
. python-packages.sh
. apply-config.sh
sudo systemctl reboot
