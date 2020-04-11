#!/bin/ash

set -e

source /etc/dhcp.env

echo RUNNING INSTALL

image=ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz
tftp -g -r "$image" $router

zcat $image | dd of=/dev/mmcblk0 bs=1M

mkdir -p /mnt
mkdir -p boot
mount /dev/mmcblk0p1 /boot
mount /dev/mmcblk0p2 /mnt

wget -O - https://github.com/rancher/k3os/releases/download/v0.9.0/k3os-rootfs-arm.tar.gz | tar zxvf - --strip-components=1 -C /mnt

cat >> /boot/config.txt <<EOF
framebuffer_width=800
framebuffer_height=480

#arm_64bit=1
EOF

#cat  > /boot/cmdline.txt <<EOF
#root=/dev/mmcblk0p2 init=/sbin/init rw rootwait elevator=deadline
#EOF

# if 64 bit, remember to update config.txt with arm_64bit=1 and use kernel8.img instead of kernel7l.img
#tftp -g -l /boot/kernel7.img -r vmlinuz-5.3.0-1018-raspi2 $router

sync

umount /boot
umount /mnt

echo Successful Installation
