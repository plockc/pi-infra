### Busybox
The busybox binary needs to be compiled on the build node to be the correct architecture.  After building it will go into the tdtp directory so it can be pulled by the init scripts.

```env
BUSYBOX_VERSION=1.34.1
```

```r-create-file:busybox.sh
#!/bin/bash
# created by README-busybox.md
set -euo pipefail

BUSYBOX_VERSION=%:BUSYBOX_VERSION:%
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
```
