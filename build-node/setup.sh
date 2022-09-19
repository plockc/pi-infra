#!/bin/bash
# created by README-build-node.md
set -euo pipefail
cd build-node
. upgrade.sh
. packages.sh
. python-packages.sh
. download-ubuntu.sh
. verify-device.sh
. unpack-ubuntu-onto-device.sh
. mount-ubuntu-from-device.sh
. copy-files.sh
. unmount.sh
