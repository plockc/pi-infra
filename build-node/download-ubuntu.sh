#!/bin/bash
# created by README-build-node.md
set -euo pipefail
wget --no-clobber http://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}.${UBUNTU_PATCH_VERSION}-preinstalled-desktop-arm64+raspi.img.xz
