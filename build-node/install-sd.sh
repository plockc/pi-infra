#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
source vars.sh
. download-ubuntu.sh
. verify-device.sh
. unpack-ubuntu-onto-device.sh
. mount-ubuntu-from-device.sh
. apply-config-to-sd-card.sh
. unmount.sh
