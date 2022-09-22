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
wget ${router}/$IMAGE
```

Write the image to disk then mount the partitions
```append-file:install.sh

echo Writing image to System SD Card
xzcat $IMAGE | pv | dd of=/dev/mmcblk0 bs=1M
```

Verify the partitions
```append-file:install.sh
echo Detecting partitions
partprobe /dev/mmcblk0

echo Mounting partitions
mkdir -p /mnt
mkdir -p sdboot
mount /dev/mmcblk0p1 sdboot
mount /dev/mmcblk0p2 /mnt
```

Stop cloud init configuration
```append-file:install.sh
sudo touch /etc/cloud/cloud-init.disabled
```

if dhclient were being used, then this script would update the hostname based on the DHCP hostname sent if placed in /etc/dhcp/dhclient-exit-hooks.d/hostname, however systemd-networkd uses it's own client.  You can `dhclient -r eth0` to remove lease then `dhclient -d eth0` to test (ctrl-c to exit the foreground process).
```
case "$reason" in
    BOUND | RENEW | REBOOT | REBIND)
        hostname $new_host_name
        echo $new_host_name > /etc/hostname
    ;;
esac
```

This script works with systemd-networkd (ubuntu server), can be tested with `systemctl renew eth0` and checked with `systemctl status networkd-dispatcher` and link info with `networkctl status`.
```append-file:install.sh
(cat <<EOF
#!/bin/bash
if host $ADDR; then
    new_name=$(host $ADDR | sed 's/.* \(.*\)\.$/\1')
    echo $new_name > /etc/hostname
    hostname $new_name
fi
EOF
) | tee /etc/networkd-dispatcher/configured.d/hostname > /dev/null
```


```append-file:install.sh
if [[ hostname =~ cp[0-9]+ ]]; then
    wget 192.168.8.1/cp.sh
fi
```

Clean up and end the installation
```append-file:install.sh
echo Sync-ing disks
sync

echo Unmounting partitions
umount sdboot /mnt

echo Successful Installation
```
