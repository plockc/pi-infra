#!/bin/bash
# created by README-busybox.md
set -euo pipefail

BUSYBOX_VERSION=1.34.1
BUSYBOX=busybox-${BUSYBOX_VERSION}.tar.bz2
wget --no-clobber "https://www.busybox.net/downloads/$BUSYBOX"
tar --bzip2 -xf "$BUSYBOX"
if [ ! -f busybox-$BUSYBOX_VERSION/busybox ]; then
    cd busybox-$BUSYBOX_VERSION
    make defconfig
    LDFLAGS="--static" make -j2
else
    echo busybox $BUSYBOX_VERSION already built
fi
cp busybox-$BUSYBOX_VERSION/busybox .
