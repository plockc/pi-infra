#!/bin/bash

set -euo pipefail

FIRMWARE_ARCHIVE=firmware_master.tgz
[[ ! -f "$FIRMWARE_ARCHIVE" ]] && wget -O "$FIRMWARE_ARCHIVE" https://github.com/raspberrypi/firmware/archive/master.tar.gz

wget --no-clobber http://cdimage.ubuntu.com/releases/18.04.4/release/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz

version=1.31.1
BUSYBOX=busybox-$version.tar.bz2
wget --no-clobber "https://www.busybox.net/downloads/$BUSYBOX"
tar --bzip2 -xf "$BUSYBOX"
tar -zcf busybox.tgz busybox-$version

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
  echo -e "sudo dd if=/dev/zero of=\"/dev/$DEVICE\" bs=1M count=5\n" 
  exit 1
fi

xzcat --stdout ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz | pv | sudo dd of=/dev/$DEVICE bs=1M
sudo partprobe 

PIROOT=/media/$USER/piroot
sudo mkdir -p /media/$USER/piboot "$PIROOT"
sudo mount /dev/${DEVICE}1 /media/$USER/piboot
sudo mount /dev/${DEVICE}2 "$PIROOT"


pushd "$PIROOT"/etc/netplan
sudo cp ~1/gateway/{wlan0,eth{0,1}}.yaml .
popd

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/gateway/cloud-init/disable-network-config.cfg 99-disable-network-config.cfg
popd

pushd $PIROOT/etc
sudo cp ~1/gateway/resolved.conf systemd/resolved.conf
sudo cp ~1/gateway/cloud-init/hostname.cfg cloud/cloud.cfg.d/99-hostname.cfg
popd

if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

pushd "$PIROOT"/etc/cloud/cloud.cfg.d
echo "ssh_authorized_keys" | sudo tee 99-ssh_authorized_keys.cfg 2>/dev/null
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat $f)" | sudo tee -a 99-ssh_authorized_keys.cfg 2>/dev/null
done
popd


pushd "$PIROOT"/etc/cloud/cloud.cfg.d
sudo cp ~1/gateway/cloud-init/packages.cfg 99-packages.cfg
popd

pushd "$PIROOT"/etc
sudo sed -i 's/^#net.ipv4.ip_forward/net.ipv4.ip_forward/' sysctl.conf
sudo mkdir -p iptables
sudo cp ~1/gateway/rules.v4 iptables/
popd

pushd "$PIROOT"/etc
sudo cp ~1/gateway/dnsmasq/pocket.conf dnsmasq.d/pocket
sudo cp ~1/gateway/dnsmasq/hosts hosts.dnsmasq
sudo cp ~1/gateway/dnsmasq/resolv.conf resolv.dnsmasq.conf
popd

pushd "$PIROOT"
sudo mkdir -p tftpboot
sudo tar -C tftpboot -zxf ~1/"$FIRMWARE_ARCHIVE" firmware-master/boot --strip-components=2
popd

chmod 755 gateway/first-boot/busybox-compile-and-install.sh
sudo cp busybox.tgz gateway/first-boot/busybox-compile-and-install.sh "$PIROOT/root"

sudo cp installer/init{,2} "$PIROOT"/root/

sudo chmod 755 installer/udhcpc-configure-interface.sh
sudo cp installer/{udhcpc-configure-interface.sh,initramfs.sh} "$PIROOT"/root/

sudo cp gateway/first-boot/run-cmd.cfg "$PIROOT"/etc/cloud/cloud.cfg.d/99-run-cmd.cfg

pushd "$PIROOT"/tftpboot/
sudo cp ~1/installer/install.sh .
sudo cp ~1/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz .
popd

sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

