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

set -euo pipefail

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
touch /mnt/etc/cloud/cloud-init.disabled
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

Some info: [network-dispatcher](https://gitlab.com/craftyguy/networkd-dispatcher#usage)
```append-file:install.sh
(cat <<EOF
#!/bin/bash
for addr in $IP_ADDRS; do
if host $addr > /dev/null; then
        new_name=$(host $addr 192.168.8.1 | grep " domain name pointer " | sed 's/.* \(.*\)\.$/\1/')
        if [ "$new_name" != "" ]; then
                echo $new_name > /etc/hostname
                hostname $new_name
                echo "Updated hostname to $new_name"
        fi
fi
done
EOF
) | tee /mnt/etc/networkd-dispatcher/configured.d/hostname > /dev/null
chmod 755 /mnt/etc/networkd-dispatcher/configured.d/hostname
```

Add helm (for applications on Kubernetes) CLI
```append-file:install.sh
chroot /mnt snap install helm --classic
```

Add kernel modules that are missing (like vxlan needed for k3s)
```append-file:install.sh
chroot /mnt apt install linux-modules-extra-raspi
```

update kernel commandline, use legacy names for network like eth0, and add cgroups, needed for running containers in kubernetes
```append-file:install.sh
sed -i -e 's/$/ net.ifnames=0 cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory' sdboot/cmdline.txt
```

Clean up and end the installation
```append-file:install.sh
echo Sync-ing disks
sync

echo Unmounting partitions
umount sdboot /mnt

echo Successful Installation
```
