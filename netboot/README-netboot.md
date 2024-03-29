# Raspi Specific NetBoot

The raspberry pi 4 needs to be configured for netboot, easist is to install the lite raspberry pi os lite (and keep that card around)

```
sudo apt update
sudo apt install -y rpi-eeprom
sudo rpi-eeprom-update
```

If there is an updte needed will say UPDATE AVAILABLE.  If so

```
sudo rpi-eeprom-update -d -a
sudo systemctl reboot
```

After eeprom is updated, updte the BOOT_ORDER
```
sudo EDITOR=vim rpi-eeprom-config --edit
```

ensure the BOOT_ORDER is set to `BOOT_ORDER=0xf21`, save and exit, then reboot.

I'm not sure if you have to reboot intto the PI (in other words, not sure exactly when eeprom is updated, immediately or only on boot)

---

This script assumes it is running on a configured gateway, see README-gateway.md

## Upgrade Gateway to Netboot

These vars can be edited adding `-a` arg to `rundoc run`

```env
UBUNTU_VERSION=22.04
UBUNTU_PATCH_VERSION=1
```

Setup netboot for raspberry pi 4 of Ubuntu server (pi 3 memory too small)
```create-file:setup-netboot.sh
#!/bin/bash
# created by README-netboot.md
set -euo pipefail
. download-os.sh
. darkhttpd.sh
. firmware.sh
. initramfs.sh
. tftp.sh
```

To set hostnames for Pis, update a file in `/etc/dnsmasq.d` such as `k8s-hosts` with contents like below to set the hostname and IP based on the MAC.
```
dhcp-host=dc:a6:32:31:82:a5,cp1,192.168.8.10
```

### Download ubuntu 

```r-create-file:download-os.sh
#!/bin/bash
# created by README-netboot.md
set -euo pipefail

FILE=ubuntu-%:UBUNTU_VERSION:%.%:UBUNTU_PATCH_VERSION:%-preinstalled-server-armhf+raspi.img.xz
FILE64=ubuntu-%:UBUNTU_VERSION:%.%:UBUNTU_PATCH_VERSION:%-preinstalled-server-arm64+raspi.img.xz
wget --no-clobber http://cdimage.ubuntu.com/releases/%:UBUNTU_VERSION:%/release/$FILE
wget --no-clobber http://cdimage.ubuntu.com/releases/%:UBUNTU_VERSION:%/release/$FILE64
wget --no-clobber https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2022-09-26/2022-09-22-raspios-bullseye-arm64-lite.img.xz
```

### Firmware and Kernel

Pull down the raspberry pi firmware, included there is a kernel that can work for netboot as it has statically compiled device drivers

Extract the contents of the "boot" directory of the firmware tarball into the tftpboot directory

```create-file:firmware.sh
#!/bin/bash
# created by README-netboot.md
set -euo pipefail

FIRMWARE_ARCHIVE=firmware_master.tgz

[[ ! -f "$FIRMWARE_ARCHIVE" ]] && wget -O "$FIRMWARE_ARCHIVE" https://github.com/raspberrypi/firmware/archive/master.tar.gz

sudo mkdir -p firmware 
sudo tar -C firmware  --strip-components=2 -zxf "$FIRMWARE_ARCHIVE" firmware-master/boot
```

The config.txt is pulled by Pi, the directive "initramfs" specifies the file name for the initramfs ("initramfs.img", also stored on tftp) and it should immediately follow the kernel, the kernel knows how to find it.
```append-file:firmware.sh
echo -e "[pi4]\nkernel=kernel8.img\n\ninitramfs initramfs.img followkernel" | sudo tee config.txt >/dev/null
```

## TFTP

### DarkHttpd

Create the systemd service file so it runs on startup and restarts if a failure.
```r-create-file:darkhttpd.service
[Unit]
Description=Darkhttpd Web Server for /tftpboot
After=network.target

[Service]
Type=simple
ExecStart=/sbin/darkhttpd /tftpboot --addr ${GW_ADDR}
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
```

Configure dnsmasq for tftp

```create-file:dnsmasq-tftp-conf
enable-tftp
tftp-root=/tftpboot
pxe-service=0,"Raspberry Pi Boot   "
```

## Installer

The installer is composed of two parts, a kernel and a initramfs which is a filesystem loaded into ram instead of read off disk.  Both of these will be delivered over tftp during netboot.  The initramfs filesystem will be binaries provided by busybox, as it only needs limited features to perform the installation.

To create the initramfs, a working directory will be created and busybox installation will target the work directory and create symlinks to busybox for all the binaries it replaces.

### gateway first boot to create initramfs

The initramfs sets up networking and does installation within an init script.  Busybox installed an init script, we need to replace it.  The creation of the initramfs is run during first boot of the gateway.

The initramfs goal is to run an install script.  The install script itself is a download from the gateway as it's easier to modify the install script on the gateway outside of the initramfs.

#### init scripts - configuring DHCP interface

To be able to download the install script, networking must be set up.  The initramfs uses udhcpc (from busybox) for DHCP. udhcpc after plumbing an interface runs a script with environment variables as inputs which can be used to configure the interface.

This script is pointed to in udhcpc config.
```create-file:udhcpc-configure-interface.sh
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
```

The kernel has a configuration for an executable to run and the default is /init.
This is the init script, it does some basic setup for the kernel, then runs another script we'll call init2 and include in the initramfs.  The first script's runtime environment is hampered so we'll call a second script after runtime environment is improved and it can behave like a normal script. 

This is `/init`:
```create-file:init
#!/bin/sh
set -euo pipefail

mount -t proc none /proc
mount -t sysfs none /sys
echo Starting init...
echo /sbin/mdev > /proc/sys/kernel/hotplug
mknod /dev/null c 1 3
/sbin/mdev -s
exec setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1 /sbin/init2'
```

This is `/sbin/init2`, it will bring up the primary interface and start udhcpc on that interface.  After the interface is configured, pull down an install script from tftp that knows how to install and configure the OS.
```create-file:init2
#!/bin/sh

echo Starting init2
# keep the kernel messages from appearing on screen
#echo 0 > /proc/sys/kernel/printk

# bring link up after we wait a few seconds (1 is not enough) for it to appear so DHCP client can send packets
sleep 3
ip link set dev eth0 up

echo Starting udhcpc
if udhcpc; then
    source /etc/dhcp.env
    echo Pulling install.sh from $router
    if tftp -g -l /root/install.sh -r install.sh $router ; then
        chmod 755 /root/install.sh
        echo Install script retrieved
    else
        echo No install.sh found
    fi
    [ -x /root/install.sh ] && /root/install.sh && reboot -f
    echo Failed installation, dropping to ash shell
fi
/bin/ash
reboot -f
```

### create initramfs image

The initramfs image is a single file representing a complete OS image and filesystem.  The initramfs created here solely does an OS installation.  The pi powers on with netboot enabled, looks for tftp server and pulls config.txt which points to the initramfs created here. will be created from a local directory (we'll use bbroot) that will have the entire filesystem layed out in that directory.  We'll need:

* init scripts
* busybox binary and links
* kernel

Create a local directory to be working directory to collect the initramfs filesystem
```create-file:initramfs.sh
#!/bin/bash
# created from README-netboot.md
set -euo pipefail

mkdir -p bbroot
pushd bbroot
```

Prepare all the items needed for the kernel and some glibc libs that can't be statically compiled in busybox for dns.

```append-file:initramfs.sh
mkdir -p {proc,sys,dev,etc,usr/lib,usr/sbin,usr/bin,bin,sbin,lib/arm-linux-gnueabihf}
sudo cp /lib/arm-linux-gnueabihf/libnss* lib/arm-linux-gnueabihf/
```

Setup busybox
```append-file:initramfs.sh
if [ ! -f ~1/busybox ]; then
    echo busybox binary is missing, can create it on build node and place in this directory
fi
cp ~1/busybox sbin/
sudo chroot . /sbin/busybox --install
```

overwrite the busybox init script in the initramfs directory and copy init2 and the dhcp configuration scripts
```append-file:initramfs.sh
rm sbin/init
chmod 755 ~1/init{,2} ~1/udhcpc-configure-interface.sh
cp ~1/init2 sbin/
cp ~1/init .
mkdir -p usr/share/udhcpc
cp ~1/udhcpc-configure-interface.sh usr/share/udhcpc/default.script
```

Create the initramfs from the working directory and place in tftpboot dir
```append-file:initramfs.sh
find . | cpio -H newc -o | gzip > ~1/initramfs.img
```

Finish the initramfs.sh
```append-file:initramfs.sh
popd
```

This is tftp.sh, it will copy all the assets to tftp directory for netboot, configure dnsmasq for network

Copy the install script, and OS images
```r-create-file:tftp.sh
#!/bin/bash
# created by README-netboot.md
set -euo pipefail

sudo cp darkhttpd /sbin/
sudo cp darkhttpd.service /etc/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable darkhttpd
sudo systemctl start darkhttpd

sudo cp pv /tftpboot

pushd /tftpboot
sudo rsync -rc ~1/{install.sh,config.txt,initramfs.img,firmware/*} .
sudo rsync -c ~/2022-09-22-raspios-bullseye-*-lite.img.xz .
sudo cp ~/.ssh/authorized_keys .
cat ~/.ssh/id_ed25519.pub | sudo tee -a authorized_keys > /dev/null
sudo cp ~1/k8s/init-kubernetes.sh ~1/k8s/kubernetes-prep.sh .
sudo cp ~1/dhclient-hostname.sh .
sudo cp ~1/configure-os.sh .
# TODO: maybe not needed
#echo "net.ifnames=0" | sudo tee cmdline.txt >/dev/null
echo ubuntu:$(openssl passwd -6 ubuntu) | sudo tee -a userconf.txt > /dev/null
popd

sudo cp dnsmasq-tftp-conf /etc/dnsmasq.d/tftpd.conf
sudo systemctl restart dnsmasq
```

## Troubleshooting

- 7 green blinks mean kernel is not found
- ubuntu kernel probably has some of the support as modules and needs matching initramfs
- if the screen scales to a higher resolution and becomes blurry (cheap 5" screens off of amazon), set framebuffer_width and framebuffer_height in config.txt for the actual hardware

## Further Reading

https://www.raspberrypi.org/documentation/configuration/config-txt/README.md

## Chain build other READMEs
```bash
rundoc run README-install.md
(cd k8s && rundoc run README-init-kubernetes.md && rundoc run README-kubernetes-prep.md)
```
