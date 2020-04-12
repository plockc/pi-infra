#!/bin/bash

set -euo pipefail

FIRMWARE_ZIP=$PWD/firmware_master.zip
wget -O "$FIRMWARE_ZIP" --no-clobber https://github.com/raspberrypi/firmware/archive/master.zip

wget --no-clobber http://cdimage.ubuntu.com/releases/18.04.4/release/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz

version=1.31.1
BUSYBOX=busybox-$version.tar.bz2
wget --no-clobber "https://www.busybox.net/downloads/$BUSYBOX"
tar --bzip2 --strip-components 1 -xf "$BUSYBOX" | tar zcf busybox.tgz
BUSYBOX=busybox.tgz

while [[ "$DEVICE" == "" ]]; do
    DEVICE=$(cat .device)
    DEVICES="$(ls /sys/bus/usb/devices/*/*/host*/target*/*/block)"
    read -p "Devices found $DEVICES, choose one as DEVICE" DEVICE
    echo "$DEVICE" > .device
fi

foundFS=$(lsblk --fs /dev/$DEVICE)
if [[ "$foundFS" != "" ]]; then
  echo -e "Found filesystems, please clear sd card:\n$foundFS"
  exit 1
fi

xzcat --stdout ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz | pv | sudo dd of=/dev/$DEVICE bs=1M

PIROOT=/media/$USER/piroot
sudo mkdir -p /media/$USER/piboot "$PIROOT"
sudo mount /dev/${DEVICE}1 /media/$USER/piboot
sudo mount /dev/${DEVICE}2 "$PIROOT"

pushd "$PIROOT"/etc/netplan
cp ~1/gateway/eth0.yml ~1/gateway/eth1.yml .
popd

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
cp ~1/gateway/cloud-init/disable-network-config.cfg 99-disable-network-config.cfg
popd

pushd $PIROOT/etc
cp ~1/gateway/resolv.dnsmasq.conf resolv.dnsmasq.conf
cp ~1/gateway/resolved.conf systemd/resolved.conf
cp ~1/gateway/cloud-init/99-hostname.cloud-init.cfg cloud/cloud.cfg.d/99-hostname.cfg
popd

if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
echo "ssh_authorized_keys" > 99-ssh_authorized_keys.cfg
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat ~/.ssh/$f)" >> 99-ssh_authorized_keys.cfg
done
popd

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
cp ~1/gateway/cloud-init/packages.cfg 99-packages.cfg
popd

pushd "$PIROOT"/etc
sed -i 's/^#net.ipv4.ip_forward/net.ipv4.ip_forward/' sysctl.conf
cp ~1/gateway/rules.v4 etc/iptables/

pushd "$PIROOT"/etc
cp ~1/gatway/dnsmasq/pocket.conf dnsmasq.d/pocket
cp ~1/hosts hosts.dnsmasq
cp ~1/resolv.conf etc/resolv.dnsmasq.conf
popd

pushd "$PIROOT"/root
cp ~1/gateway/first-boot/"$BUSYBOX" ~1/gateway/first-boot/busybox-compile-and-install.sh .
popd

cp ~1/installer/init{,2} "$PIROOT"/root/

cp installer/initramfs.sh "$PIROOT"/root/

cp installer/run-cmd.cfg "$PIROOT"/etc/cloud/cloud.cfg.d/99-run-cmd.cfg

pushd "$PIROOT"/tftpboot/
cp ~1/installer/install.sh .
cp ~1/installer/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz .
popd

sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

