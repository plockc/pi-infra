#!/bin/bash
# created by README-build-node.md
set -euo pipefail
. sshkey.sh
. upgrade.sh
. packages.sh
. darkhttpd.sh
. python-packages.sh
. apply-config.sh
sudo systemctl reboot
