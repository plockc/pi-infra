#!/bin/bash

set -euo pipefail

tar --bzip2 -xv /root/$BUSYBOX
cd busybox-$version
make defconfig
LDFLAGS="--static" make -j2
mkdir /root/bbroot
LDFLAGS="--static" make install CONFIG_PREFIX=/root/bbroot
