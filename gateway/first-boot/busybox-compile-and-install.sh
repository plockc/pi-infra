#!/bin/bash

set -euo pipefail

mkdir -p busybox
tar -C busybox --strip-components 1 -zxvf /root/busybox.tgz
cd busybox
make defconfig
LDFLAGS="--static" make -j2
mkdir /root/bbroot
LDFLAGS="--static" make install CONFIG_PREFIX=/root/bbroot
