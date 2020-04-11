# Gateway

This sets up the gateway (with NAT) for a pocket network using dnsmasq for DNS, TFTP, and DHCP.  It's expected the hosts on the pocket network are Raspberry Pi machines versions 3 or 4 and primarily running k3os.

Also, the host the script is run on needs to be on the same network that the external interface on the firewall gateway is on.

## Executing this script

Install rundoc, extract the script embedded in this README, the run it

```usage
pip3 install rundoc
rundoc run README.md
sudo bash gateway.sh
```

## Download

Download raspberry pi boot firmware and kernel

```bash
FIRMWARE_ZIP=$PWD/firmware_master.zip
wget -O "$FIRMWARE_ZIP" --no-clobber https://github.com/raspberrypi/firmware/archive/master.zip
```

Pull ubuntu preinstalled server, which is a compacted complete disk image

```bash
wget --no-clobber http://cdimage.ubuntu.com/releases/18.04.4/release/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz
```

```bash
version=1.31.1
BUSYBOX=busybox-$version.tar.bz2
wget --no-clobber "https://www.busybox.net/downloads/$BUSYBOX"
tar --bzip2 --strip-components 1 -xf "$BUSYBOX" | tar zcf busybox.tar.gz
BUSYBOX=busybox.tgz
```

## Install

Make sure we fail on errors

```bash
set -euo pipefail
```

Find SD Card (check is for USB devices: not generic, sorry)

```bash
while [[ "$DEVICE" == "" ]]; do
    DEVICE=$(cat .device)
    DEVICES="$(ls /sys/bus/usb/devices/*/*/host*/target*/*/block)"
    read -p "Devices found $DEVICES, choose one as DEVICE" DEVICE
    echo "$DEVICE" > .device
fi
```

make sure that filesystems are not mounted

```bash
foundFS=$(lsblk --fs /dev/$DEVICE)
if [[ "$foundFS" != "" ]]; then
  echo -e "Found filesystems, please clear sd card:\n$foundFS"
  exit 1
fi
```

Unpack ubuntu onto the selected device

```bash
xzcat --stdout ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz | pv | sudo dd of=/dev/$DEVICE bs=1M
```

Mount the ubuntu partitions

```bash
sudo mkdir -p /media/$USER/pi{b,r}oot
sudo mount /dev/${DEVICE}1 /media/$USER/piboot
sudo mount /dev/${DEVICE}2 /media/$USER/piroot
pushd .
cd /media/$USER/piroot
```

## Network Interfaces

Set up interfaces.  `eth0` is connected to external network, while the pocket network will be on USB on `eth1`, raspberry pi 4 would have much better network speeds than earlier versions.

```create-file:eth0.yml#files
network:
    version: 2
    renderer: networkd
    ethernets:
        eth0:
            optional: true
            dhcp4: false
            addresses: [192.168.3.1/24]
            # no gateway, we don't want this host to route over the pocket
            nameservers:
                    search: [k8s.local]
                    addresses: [192.168.3.1, 1.1.1.1]
```

Interface for external network as DHCP
```create-file:eth1.yml#files
network:
    version: 2
    renderer: networkd
    ethernets:
        eth1:
            optional: true
            dhcp4: true
```

Example for wireless network for external interface

```create-file:wlan0.yml#files
network:
    version: 2
    renderer: networkd
    wifis:
        wlan0:
            # allow OS to start (while still building boot sequeuence)
            optional: true
            # do not release IP address
            critical: true
            dhcp4: true
            access-points:
                "SSID":
                    password: "PASSWORD"
```

Copy the network files (adjust as needed prior to running gateway.sh)

```bash
cp eth0.yml etc/netplan/eth0.yaml
cp eth1.yml etc/netplan/eth1.yaml
```

I forget why we do this, think it's to avoid cloud init from conflicting from our manual setup of netplan
```create-file:disable-network-config.cloud-init.cfg#files
network: {config: disabled}"
```

Copy the configuration files
```bash
cp disable-network-config.cloud-init.cfg etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```


## Hostname resolution

Set the hostname

```create-file:hostname.cloud-init.cfg#files
hostname: infra1
```

Turn off systemd DNS stub
```create-file:resolved.conf#files
echo DNSStubListener=no
```

Copy the configuration files to mounted ubuntu filesystem
```bash
cp resolv.dnsmasq.conf etc/resolv.dnsmasq.conf
cp resolved.conf etc/systemd/resolved.conf
cp 99-hostname.cloud-init.cfg etc/cloud/cloud.cfg.d/99-hostname.cfg
```


## SSH

Add ssh keys

```bash
if ! ls ~/.ssh/id_*.pub; then
  echo No ssh keys in ~/.ssh
fi

echo "ssh_authorized_keys" > etc/cloud/cloud.cfg.d/99-ssh_authorized_keys.cfg
for f in $(ls ~/.ssh/id_*.pub); do
  echo "  - $(cat ~/.ssh/$f)" >> etc/cloud/cloud.cfg.d/99-ssh_authorized_keys.cfg
done
```

## Packages

```create-file:packages.cloud-init.cloud-init.cfg#files
packages:
  - dnsmasq
  - rng-tools
  - make
  - gcc
  - iptables-persistent
  - netfilter-persistent
  - iptables-persistent
  - netfilter-persistent
```

Copy the configuration files
```bash
cp packages.cloud-init.cloud-init.cfg etc/cloud/cloud.cfg.d/99-packages.cfg
```


## Firewall

Enable forwarding

```bash
sed -i 's/^#net.ipv4.ip_forward/net.ipv4.ip_forward/' etc/sysctl.conf
```

```create-file:rules.v4#files
*filter
:INPUT ACCEPT [1777:151380]
:FORWARD ACCEPT [4:336]
:OUTPUT ACCEPT [1853:3675835]
COMMIT
*nat
:PREROUTING ACCEPT [6:1474]
:INPUT ACCEPT [5:1390]
:OUTPUT ACCEPT [4:301]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -o eth1 -j MASQUERADE
COMMIT
```

```bash
cp rules.v4 etc/iptables/
```


## dnsmasq

```create-file:pocket.dnsmasq.conf#files
listen-address=192.168.3.1
# default is 150
cache-size=1000
interface=eth0
domain=k8s.local
# gateway
dhcp-option=3,0.0.0.0
# dns servers
dhcp-option=6,192.168.3.1
# static route
dhcp-option=121,0.0.0.0/0,192.168.3.1
dhcp-range=192.168.3.150,192.168.3.250,5m
log-dhcp
enable-tftp
tftp-root=/tftpboot
pxe-service=0,"Raspberry Pi Boot   "
bogus-priv
domain-needed
# have a special resolve configuration that dnsmasq uses
# which allows system to point to external network dns
resolv-file=/etc/resolv.dnsmasq.conf
addn-hosts=/etc/hosts.dnsmasq
```

```create-file:hosts.dnsmasq#files
192.168.3.1 infra1
```

```create-file:resolv.dnsmasq.conf#files
nameserver 1.1.1.1
options edns0
search k8s.local
```

Copy the configuration files
```bash
cp pocket.dnsmasq.conf etc/dnsmasq.d/k8s_network
cp hosts.dnsmasq etc/hosts.dnsmasq
cp resolv.dnsmasq.conf etc/resolv.dnsmasq.conf
```


## Firmware

also in there is a kernel that can work for netboot as it has statically compiled device drivers

```
mkdir tftpboot
unzip "$FIRMWARE_ZIP" firmware-master/boot/**"-d /tftpboot
```

## Installer


The installer is composed of two parts, a kernel and a initramfs which is a filesystem loaded into ram instead of read off disk.  Both of these will be delivered over tftp during netboot.  The initramfs filesystem will be binaries provided by busybox, as it only needs limited features to perform the installation.

### Busybox
The busybox binary needs to be compiled on the pi to be the correct architecture. Since the local machine is often not a raspi, this will be done as part of first time boot of the raspi gateway and placed into the tftp directory to be available to raspis being booted.

Copy the downloaded archive so it's available for compiling on the gateway

```bash
cp "$BUSYBOX" root/
```

This is the beginning of a script run at first boot to unpack and compile it.

```create-file:busybox.sh#files
#!/bin/bash

set -euo pipefail

tar --bzip2 -xv /root/$BUSYBOX
cd busybox-$version
make defconfig
LDFLAGS="--static" make -j2
```

To create the initramfs, a working directory will be created and busybox installation will target the work directory and create symlinks to busybox for all the binaries it replaces.

```append-file:busybox.sh#files
mkdir /root/bbroot
LDFLAGS="--static" make install CONFIG_PREFIX=/root/bbroot
```

Copy the busybox script to the sd card

```bash
cp busybox.sh root/
```

### gateway first boot to create initramfs

The initramfs sets up networking and does installation within an init script.  Busybox installed an init script, we need to replace it.  The creation of the initramfs is run during first boot of the gateway.

The initramfs goal is to run an install script.  The install script itself is a download from the gateway as it's easier to modify the install script on the gateway outside of the initramfs.

#### init scripts - configuring DHCP interface

To be able to download the script, networking must be set up.  To set up networking udhcpc runs a script with environment variables as inputs which can be used to configure the interface.

```create-file:udhcpc-configure-interface.sh#files
# not starting new shell as the dhcp variables are not exported

# can source this in other scripts
set +x
env > /etc/dhcp.env

if [[ "\$1" != "bound" ]]; then
    echo DHCP interface not bound ...
    exit 0
fi
ip addr add \$ip/\$mask dev \$interface
ip route add default via \$router dev \$interface
echo nameserver \$dns > /etc/resolv.conf
echo Networking is configured
if tftp -g -l /root/install.sh -r install.sh \$router 2>/dev/null; then
    chmod 744 /root/install.sh
    echo Install script retrieved
else
    echo No install.sh found
fi
```

This init script allows a second init script to behave like a normal script

```create-file:init#files
#!/bin/sh
set -euo pipefail

mount -t proc none /proc
mount -t sysfs none /sys
echo /sbin/mdev > /proc/sys/kernel/hotplug
mknod /dev/null c 1 3
/sbin/mdev -s
exec setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1 /sbin/init2'
```

This script downloads and installs the install script.  

```create-file:init2#files
#!/bin/sh

# keep the kernel messages from appearing on screen
echo 0 > /proc/sys/kernel/printk

# bring link up so DHCP client can send packets
ip link set dev eth0 up

echo Starting udhcpc
if udhcpc; then
    [ -x /root/install.sh ] && /root/install.sh && reboot -f
fi
/bin/ash
```

Copy the init scripts to sd card so can be used during first boot
```bash
cp init init2 root/
```

#### create initramfs image

Prepare all the items needed for the kernel and some glibc libs that can't be statically compiled in busybox for dns.

```create-file:initramfs.sh#files
#!/bin/sh
set -euo pipefail

cd /root/bbroot
mkdir -p {proc,sys,dev,etc,usr/lib,bin,sbin,lib/arm-linux-gnueabihf}
cp /lib/arm-linux-gnueabihf/libnss* lib/arm-linux-gnueabihf/
```

overwrite the busybox init script in the initramfs directory and copy init2 and the dhcp configuration script
```append-file:initramfs.sh#files
cp /root/init{,2}  sbin/
mkdir -p usr/share/udhcpc
cp /root/udhcpc-configure-interface.sh usr/share/udhcpc/default.script
sudo chmod 744 sbin/init sbin/init2 usr/share/udhcpc/default.script
```

Create the initramfs to tftpboot dir
```append-file:initramfs.sh#files
find . | cpio -H newc -o | gzip > /tftpboot/initramfs.img
```

```create-file:run-cmd.cfg#files
runcmd:
  - /root/busybox.sh
  - /root/initramfs.sh
```

This cloud init fragment will run the first time boot scripts to create the initramfs

Copy the script to create the initramfs to the sd card for reference by first boot
```bash
cp initramfs.sh root/
```

Copy the cloud init configuration to the sd card
```bash
cp run-cmd.cfg etc/cloud/cloud.cfg.d/99-run-cmd.cfg
```

## Install script


```create-file:install.sh#files
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
```

copy the install script, and OS images
```bash
cp install.sh root/tftpboot/
cp ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz /root/tftpboot/
```

## Complete

Unmount the sd card partitions

```bash
sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}
```

## Notes

Manually update network interface configuration by editing files in `/etc/netplan`

```
sudo netplan generate
sudo netplan apply
```

## Troubleshooting

- 7 green blinks mean kernel is not found
- ubuntu kernel probably has some of the support as modules and needs matching initramfs

## Further Reading


https://www.raspberrypi.org/documentation/configuration/config-txt/README.md
