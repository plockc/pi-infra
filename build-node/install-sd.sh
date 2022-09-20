#!/bin/bash
# created by README-install-ubuntu-on-sd-card.md
set -euo pipefail
. download-ubuntu.sh
. verify-device.sh
. unpack-ubuntu-onto-device.sh
. cloud-init-ssh-authorized-keys.sh
. mount-ubuntu-from-device.sh
. apply-config-to-sd-card.sh
. unmount.sh
