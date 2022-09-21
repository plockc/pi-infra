# Install script

This script is run on the pi being netbooted, it will pull an OS image, then unpack it onto the disk.

It is called by init2 (which is on the initrams).

This script is run from init2 on the netbooted initramfs.


# Configuration

```env
IMAGE=ubuntu-22.04.1-preinstalled-server-armhf+raspi.img.xz
```

# Load dhcp values

Start with bash header and include all the variables from dhcp that can be used to find things
```r-create-file:install.sh
#!/bin/ash

set -e

IMAGE=%:IMAGE:%

echo RUNNING INSTALL
echo ---------------

echo Loading values determined by dhcp
source /etc/dhcp.env
```

Pull the image from tftp, the router address comes from dhcp.env
```append-file:install.sh
echo Download OS Image
tftp -g -r "$IMAGE" $router
```

Write the image to disk then mount the partitions
```append-file:install.sh

echo Writing image to System SD Card
zcat $image | dd of=/dev/mmcblk0 bs=1M
```

Verify the partitions
```append-file:install.sh
echo Detecting partitions
partprobe

echo Mounting partitions
mkdir -p /mnt
mkdir -p boot
mount /dev/mmcblk0p1 boot
mount /dev/mmcblk0p2 /mnt
```

Clean up and end the installation
```append-file:install.sh
echo Sync-ing disks
sync

echo Unmounting partitions
umount boot /mnt

echo Successful Installation
```
