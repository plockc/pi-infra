#!/bin/bash
# created by README-build-node.md
set -euo pipefail
. upgrade.sh
. packages.sh
. python-packages.sh
. apply-config.sh
sudo systemctl reboot
