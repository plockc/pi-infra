#!/bin/sh
set -euo pipefail

cd /root/bbroot
mkdir -p {proc,sys,dev,etc,usr/lib,bin,sbin,lib/arm-linux-gnueabihf}
cp /lib/arm-linux-gnueabihf/libnss* lib/arm-linux-gnueabihf/
cp /root/init{,2}  sbin/
mkdir -p usr/share/udhcpc
cp /root/udhcpc-configure-interface.sh usr/share/udhcpc/default.script
sudo chmod 744 sbin/init sbin/init2 usr/share/udhcpc/default.script
find . | cpio -H newc -o | gzip > /tftpboot/initramfs.img
