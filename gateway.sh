#!/bin/bash

set -euo pipefail

FIRMWARE_ARCHIVE=firmware_master.tgz
[[ ! -f "$FIRMWARE_ARCHIVE" ]] && wget -O "$FIRMWARE_ARCHIVE" https://github.com/raspberrypi/firmware/archive/master.tar.gz

wget --no-clobber http://cdimage.ubuntu.com/releases/18.04.4/release/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz

version=1.31.1
BUSYBOX=busybox-$version.tar.bz2
wget --no-clobber "https://www.busybox.net/downloads/$BUSYBOX"
tar --bzip2 -xf "$BUSYBOX"
BUSYBOX=busybox.tgz
tar --strip-components 1 -cf "$BUSYBOX" busybox-$version

if [[ "${DEVICE:-}" == "" ]]; then
    DEVICES="$(ls /sys/bus/usb/devices/*/*/host*/target*/*/block)"
    echo -e "\nFound devices: $DEVICES\n"
    echo -e "usage: env DEVICE=<device name e.g. sdb> $0\n"
    exit 1
fi

foundParts=$(lsblk -J "/dev/$DEVICE" | jq ".blockdevices[].children|length")
if [[ "$foundParts" != "0" ]]; then
  echo -e "Found filesystems, please umount filesystems and clear SD card partition table:\n$(lsblk --fs /dev/"$DEVICE")"
  echo -e "\nThis command will wipe the partition table:"
  echo -e "sudo dd if=/dev/zero of=\"/dev/$DEVICE\" bs=1M count=100\n" 
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

