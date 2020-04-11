FIRMWARE_ZIP=$PWD/firmware_master.zip
wget -O "$FIRMWARE_ZIP" --no-clobber https://github.com/raspberrypi/firmware/archive/master.zip

wget --no-clobber http://cdimage.ubuntu.com/releases/18.04.4/release/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz

version=1.31.1
BUSYBOX=busybox-$version.tar.bz2
wget --no-clobber "https://www.busybox.net/downloads/$BUSYBOX"
tar --bzip2 --strip-components 1 -xf "$BUSYBOX" | tar zcf busybox.tar.gz
BUSYBOX=busybox.tgz

set -euo pipefail

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

sudo mkdir -p /media/$USER/pi{b,r}oot
sudo mount /dev/${DEVICE}1 /media/$USER/piboot
sudo mount /dev/${DEVICE}2 /media/$USER/piroot
pushd .
cd /media/$USER/piroot

cp eth0.yml etc/netplan/eth0.yaml
cp eth1.yml etc/netplan/eth1.yaml

cp disable-network-config.cloud-init.cfg etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

cp resolv.dnsmasq.conf etc/resolv.dnsmasq.conf
cp resolved.conf etc/systemd/resolved.conf
cp 99-hostname.cloud-init.cfg etc/cloud/cloud.cfg.d/99-hostname.cfg

if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

echo "ssh_authorized_keys" > etc/cloud/cloud.cfg.d/99-ssh_authorized_keys.cfg
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat ~/.ssh/$f)" >> etc/cloud/cloud.cfg.d/99-ssh_authorized_keys.cfg
done

cp packages.cloud-init.cloud-init.cfg etc/cloud/cloud.cfg.d/99-packages.cfg

sed -i 's/^#net.ipv4.ip_forward/net.ipv4.ip_forward/' etc/sysctl.conf

cp rules.v4 etc/iptables/

cp pocket.dnsmasq.conf etc/dnsmasq.d/k8s_network
cp hosts.dnsmasq etc/hosts.dnsmasq
cp resolv.dnsmasq.conf etc/resolv.dnsmasq.conf

cp "$BUSYBOX" root/

cp busybox.sh root/

cp init init2 root/

cp initramfs.sh root/

cp run-cmd.cfg etc/cloud/cloud.cfg.d/99-run-cmd.cfg

cp install.sh root/tftpboot/
cp ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz /root/tftpboot/

sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

