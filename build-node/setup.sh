#!/bin/bash
# created by README-build-node.md
set -euo pipefail
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
. upgrade.sh
. packages.sh
. python-packages.sh
. apply-config.sh
sudo systemctl reboot
