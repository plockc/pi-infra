```create-file:dnsmasq-netboot.conf
domain=k8s.local
enable-tftp
tftp-root=/tftpboot
pxe-service=0,"Raspberry Pi Boot   "
```

These vars can be edited adding `-a` arg to `rundoc run`

```env
UBUNTU_VERSION=22.04
UBUNTU_PATCH_VERSION=1
```

## Raspi Specific NetBoot


```create-file:setup-netboot.sh
#!/bin/bash
# created by README-netboot.md
set -euo pipefail
. get-firmware.sh
. download-ubuntu.sh
```

#### Firmware and Kernel

Pull down the raspberry pi firmware, included there is a kernel that can work for netboot as it has statically compiled device drivers

```create-file:get-firmware.sh
#!/bin/bash
# created by README-netboot.md
set -euo pipefail

FIRMWARE_ARCHIVE=firmware_master.tgz
[[ ! -f "$FIRMWARE_ARCHIVE" ]] && wget -O "$FIRMWARE_ARCHIVE" https://github.com/raspberrypi/firmware/archive/master.tar.gz
```

```create-file:download-ubuntu.sh
#!/bin/bash
# created by README-netboot.md
set -euo pipefail
. vars.sh
FILE=ubuntu-${UBUNTU_VERSION}.${UBUNTU_PATCH_VERSION}-preinstalled-server-armhf+raspi.img.xz
if [ ! -e $FILE ]; then
    wget --no-clobber http://cdimage.ubuntu.com/releases/${UBUNTU_VERSION}/release/$FILE
fi
```

```create-file 
pushd "$PIROOT"
sudo mkdir -p tftpboot
sudo tar -C tftpboot  --strip-components=2 -zxf ~1/"$FIRMWARE_ARCHIVE" firmware-master/boot
popd
```

#### Load kernel and initramfs

Loads the initramfs right after the kernel and sets it up so kernel uses it
```bash
pushd "$PIROOT"
(cat <<EOF
initramfs initramfs.img followkernel
framebuffer_width=800
framebuffer_height=480
EOF
) | sudo tee -a tftpboot/config.txt >/dev/null
popd
```


## Installer

The installer is composed of two parts, a kernel and a initramfs which is a filesystem loaded into ram instead of read off disk.  Both of these will be delivered over tftp during netboot.  The initramfs filesystem will be binaries provided by busybox, as it only needs limited features to perform the installation.

### Busybox
The busybox binary needs to be compiled on the pi to be the correct architecture. Since the local machine is often not a raspi, this will be done as part of first time boot of the raspi gateway and placed into the tftp directory to be available to raspis being booted.

This is the beginning of a script run at first boot to unpack the archive in /root and compile busybox.

```create-file:gateway/first-boot/busybox-compile-and-install.sh#files
#!/bin/bash

set -euo pipefail

version=1.34.1
BUSYBOX=busybox-$version.tar.bz2
wget --no-clobber "https://www.busybox.net/downloads/$BUSYBOX"
tar --bzip2 -xf "$BUSYBOX"
tar -zcf busybox.tgz busybox-$version

mkdir -p busybox
tar -C busybox --strip-components 1 -zxvf /root/busybox.tgz
cd busybox
make defconfig
LDFLAGS="--static" make -j2
```

To create the initramfs, a working directory will be created and busybox installation will target the work directory and create symlinks to busybox for all the binaries it replaces.

```append-file:gateway/first-boot/busybox-compile-and-install.sh#files
mkdir /root/bbroot
LDFLAGS="--static" make install CONFIG_PREFIX=/root/bbroot
```

Copy the busybox script and the busybox archive to the sd card so it's available for first boot compile and install.

```bash
chmod 755 gateway/first-boot/busybox-compile-and-install.sh
sudo cp busybox.tgz gateway/first-boot/busybox-compile-and-install.sh "$PIROOT/root"
```

### gateway first boot to create initramfs

The initramfs sets up networking and does installation within an init script.  Busybox installed an init script, we need to replace it.  The creation of the initramfs is run during first boot of the gateway.

The initramfs goal is to run an install script.  The install script itself is a download from the gateway as it's easier to modify the install script on the gateway outside of the initramfs.

#### init scripts - configuring DHCP interface

To be able to download the script, networking must be set up.  To set up networking udhcpc runs a script with environment variables as inputs which can be used to configure the interface.

```create-file:installer/udhcpc-configure-interface.sh#files
# not starting new shell as the dhcp variables are not exported

# can source this in other scripts
set +x
env > /etc/dhcp.env

if [[ "$1" != "bound" ]]; then
    echo DHCP interface not bound ...
    exit 0
fi
ip addr add $ip/$mask dev $interface
ip route add default via $router dev $interface
echo nameserver $dns > /etc/resolv.conf
echo Networking is configured
if tftp -g -l /root/install.sh -r install.sh $router 2>/dev/null; then
    chmod 744 /root/install.sh
    echo Install script retrieved
else
    echo No install.sh found
fi
```

This init script allows a second init script to behave like a normal script

```create-file:installer/init#files
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

```create-file:installer/init2#files
#!/bin/sh

# keep the kernel messages from appearing on screen
echo 0 > /proc/sys/kernel/printk

# bring link up after we wait a few seconds (1 is not enough) for it to appear so DHCP client can send packets
sleep 3
ip link set dev eth0 up

echo Starting udhcpc
if udhcpc; then
    [ -x /root/install.sh ] && /root/install.sh && reboot -f
fi
/bin/ash
```

Copy the init scripts to sd card so can be used during first boot
```bash
sudo cp installer/init{,2} "$PIROOT"/root/
```

#### create initramfs image

Prepare all the items needed for the kernel and some glibc libs that can't be statically compiled in busybox for dns.

```create-file:installer/initramfs.sh#files
#!/bin/bash
set -euo pipefail

cd /root/bbroot
mkdir -p {proc,sys,dev,etc,usr/lib,bin,sbin,lib/arm-linux-gnueabihf}
sudo cp /lib/arm-linux-gnueabihf/libnss* lib/arm-linux-gnueabihf/
```

overwrite the busybox init script in the initramfs directory and copy init2 and the dhcp configuration script
```append-file:installer/initramfs.sh#files
rm sbin/init
cp /root/init{,2}  sbin/
mkdir -p usr/share/udhcpc
cp /root/udhcpc-configure-interface.sh usr/share/udhcpc/default.script
sudo chmod 744 sbin/init sbin/init2 usr/share/udhcpc/default.script
```

Create the initramfs to tftpboot dir
```append-file:installer/initramfs.sh#files
find . | cpio -H newc -o | gzip > /tftpboot/initramfs.img
```

```create-file:gateway/first-boot/run-cmd.cfg#files
runcmd:
  - /root/busybox-compile-and-install.sh
  - /root/initramfs.sh
  # TODO: see why dnsmasq tries to start before interface is ready
  - systemctl restart dnsmasq
```

This cloud init fragment will run the first time boot scripts to create the initramfs

Copy the script to create the initramfs to the sd card for reference by first boot
```bash
sudo chmod 755 installer/{udhcpc-configure-interface.sh,initramfs.sh}
sudo cp installer/{udhcpc-configure-interface.sh,initramfs.sh} "$PIROOT"/root/
```

Copy the cloud init configuration to the sd card
```bash
sudo cp gateway/first-boot/run-cmd.cfg "$PIROOT"/etc/cloud/cloud.cfg.d/99-run-cmd.cfg
```

## Install script

This script is run from init2 on the netbooted initramfs to install ubuntu's preinstalled server image onto the disk.

Start with bash header and include all the variables from dhcp that can be used to find things
```create-file:installer/install.sh#files
#!/bin/ash

set -e

source /etc/dhcp.env
```

Write the image to disk then mount the partitions
```append-file:installer/install.sh#files
echo RUNNING INSTALL

image=ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz
tftp -g -r "$image" $router

zcat $image | dd of=/dev/mmcblk0 bs=1M

partprobe

mkdir -p /mnt
mkdir -p boot
mount /dev/mmcblk0p1 boot
mount /dev/mmcblk0p2 /mnt
```
Clean up and end the installation
```append-file:installer/install.sh#files
sync

umount boot /mnt

echo Successful Installation
```

Copy the install script, and OS images
```bash
pushd "$PIROOT"/tftpboot/
sudo cp ~1/installer/install.sh .
sudo cp ~1/ubuntu-18.04.4-preinstalled-server-armhf+raspi3.img.xz .
popd
```

## Complete

Unmount the sd card partitions

```bash
sync
sudo umount /dev/${DEVICE}1 /dev/${DEVICE}2
sudo eject /dev/${DEVICE}

echo Completed!
```

## Serial Console

### Serial Device
Some text says ttyAMA0 would be the serial port on pins 8 and 10 on the pi, however bluetooth on pi3+ used ttyAMA0, and instead serial was moved to ttyS0 unless bluetooth was disabled in boot config `dtoverlay=pi3-disable-bt`.  Ubuntu (20 and 18?) can use serial0 which will pick the right device for you.  

### Kernel Config
Usually with serial console, two entries exist in the kernel command line for "console".  One for serial console with a baud rate, e.g.: `console=serial0,115200`.  Also the console still should go to the normal display device so another entry is for tty1.

### USB 
I paid $11 for 3 pack of EVISWIY PL2303TA USB to TTL Serial Cable, seems to work fine.  the serial port shows up as `/dev/ttyUSB0`.

### Client

(Picocom)[https://github.com/npat-efault/picocom] works well.

To collect the terminal current height and width and then run picocom assuming USB to serial port adapter.

```
tput cols
tput lines
sudo picocom -b 115200 /dev/ttyUSB0
```

Set the terminal height and width with the values collected above
```
stty rows 24 cols 80
```

Exit session with `Ctrl-a Ctrl-x`

## Notes

Manually update network interface configuration by editing files in `/etc/netplan`

```
sudo netplan generate
sudo netplan apply
```

## Troubleshooting

- 7 green blinks mean kernel is not found
- ubuntu kernel probably has some of the support as modules and needs matching initramfs
- if the screen scales to a higher resolution and becomes blurry (cheap 5" screens off of amazon), set framebuffer_width and framebuffer_height in config.txt for the actual hardware

## Further Reading

https://www.raspberrypi.org/documentation/configuration/config-txt/README.md
